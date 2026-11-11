package main

import "base:intrinsics"
import "core:slice"
import "core:mem"
import "core:fmt"
import rl "vendor:raylib"
import "core:math"
import "core:math/noise"
import "core:thread"

WORKER_THREADS :: 8

UI :: struct {
  // "color circles"
  radius: f32,
  outline_thickness: f32,

  // slider
  start_position: rl.Vector2,
  end_position: rl.Vector2,

  // apply button
  width: f32,
  height: f32,

  // line
  line_color: rl.Color,
}

main :: proc() {

  world := World {
    width_tiles = 1280,
    height_tiles = 720,
    tile_size = 1,

    seed = 1012,
    frequency = 0.002,
    octaves = 2.0,
    lacunarity = 1.0,
    amplitude = 2.0,
    persistence = 2.0,
  }

  colors: [dynamic]World_Color
  append(&colors, World_Color{99999, rl.WHITE})
  append(&colors, World_Color{10, rl.WHITE})
  append(&colors, World_Color{3, rl.GRAY})
  append(&colors, World_Color{2, rl.Color{0, 180, 0, 255}})
  append(&colors, World_Color{0, rl.Color{0, 200, 0, 255}})
  append(&colors, World_Color{-1, rl.Color{0, 180, 0, 255}})
  append(&colors, World_Color{-4, rl.Color{0, 200, 0, 255}})
  append(&colors, World_Color{-6, rl.BLUE})
  append(&colors, World_Color{-10, rl.DARKBLUE})
  append(&colors, World_Color{-99999, rl.DARKBLUE})

  rl.InitWindow(i32(world.width_tiles*world.tile_size), i32(world.height_tiles*world.tile_size), "Raylib")


  heightmap := make_heightmap(world.width_tiles, world.height_tiles)
  populate_heightmap(world, &heightmap)

  // ------------------------------------------------------------------------
  pixels_len := world.width_tiles *world.height_tiles
  alloc_size := int(pixels_len * size_of(rl.Color))
  pixels_ptr, err := mem.alloc(alloc_size)
  defer mem.free(pixels_ptr)
  if err != mem.Allocator_Error.None {
    fmt.println(err)
    panic("pixels allocation error")
  }
  pixels := slice.from_ptr(([^]rl.Color)(pixels_ptr), pixels_len)

  for x in 0..<world.width_tiles {
    for y in 0..<world.height_tiles {
      i := (y * world.width_tiles + x)
      color := noise_to_color_lerp(colors[:], heightmap[i])
      pixels[i] = color
    }
  }

  img := rl.Image {
    data = pixels_ptr,
    width = i32(world.width_tiles) * i32(world.tile_size),
    height = i32(world.height_tiles) * i32(world.tile_size),
    mipmaps = 1,
    format = rl.PixelFormat.UNCOMPRESSED_R8G8B8A8,
  }
  texture := rl.LoadTextureFromImage(img)
  // ------------------------------------------------------------------------

  // for the thread pool
  data := Worker_Data{
    world_data = &world,
    heightmap_data = heightmap,
    pixel_data = pixels,
    color_data = colors[:],
  }

  rl.SetTargetFPS(165)

  // UI logic
  holding_slider_index: int
  is_holding_color := false
  selecting_color := false
  color_select_index: int
  hovering_new_color := false
  color_cpy: rl.Color

  octaves_f32: f32

  ui := UI {
    radius = 10,
    outline_thickness = 3,

    start_position = rl.Vector2{100,100},
    end_position = rl.Vector2{f32(world.width_tiles) - 100, 100},

    width = 100,
    height = 30,

    line_color = rl.LIGHTGRAY,
  }

  timer: i64
  delta, last_time: f64

  // TODO:
  // * UI for changing algorithm values

  // TODO: future ideas
  // * additional simplex noise for ores or similar

  BASIC_CHARS :: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789… ~!@#$%^&*()-|\"':;_+={}[]\\/`,.<>?★✓👁🚫↕•"
  code_point_count: i32
  code_points := rl.LoadCodepoints(BASIC_CHARS, &code_point_count)

  apply_font_size := i32(28)
  apply_font := rl.LoadFontEx("/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf", apply_font_size, code_points, code_point_count)
  defer rl.UnloadFont(apply_font)

  rl.GuiSetFont(apply_font)

  font_size := i32(18)
  font := rl.LoadFontEx("/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf", font_size, code_points, code_point_count)
  defer rl.UnloadFont(font)

  for !rl.WindowShouldClose() {
    // Update:
    delta = rl.GetTime() - last_time
    last_time = rl.GetTime()

    if rl.IsKeyPressed(rl.KeyboardKey.Q) {
      rl.CloseWindow()
    }

    // Picking colors
    if rl.IsKeyDown(rl.KeyboardKey.X){
      selecting_color = false
    }

    if rl.GetMousePosition().y < ui.start_position.y + ui.radius + ui.outline_thickness && rl.GetMousePosition().y > ui.start_position.y || 
    rl.GetMousePosition().y > ui.start_position.y - ui.radius - ui.outline_thickness && rl.GetMousePosition().y < ui.start_position.y {
      hovering_new_color = true

      height_value: for i in 0..<len(colors) {
        circle_pos_x := min_max_normalization(colors[i].height_value, ui.start_position.x, ui.end_position.x, -10, 10)

        if rl.CheckCollisionPointCircle(
          rl.GetMousePosition(),
          rl.Vector2{circle_pos_x, ui.start_position.y},
          ui.radius + ui.outline_thickness
        ) {
          // hovering color

          // can't create new color when hovering existing color
          hovering_new_color = false

          if !is_holding_color &&
          rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
            // start holding color
            is_holding_color = true
            holding_slider_index = i
          }
          else if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) && rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) {
            // remove color on shift + right click
            ordered_remove(&colors, i)
          }
          else if rl.IsMouseButtonDown(rl.MouseButton.RIGHT) {
            // change color on right click
            selecting_color = true
            color_select_index = i
          }
        }
      }
    }
    else do hovering_new_color = false

    if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
      // Dragging colors
      if is_holding_color {
        colors[holding_slider_index].height_value = math.clamp(min_max_normalization(rl.GetMousePosition().x, -10, 10, ui.start_position.x, ui.end_position.x), -10, 10)
        if colors[holding_slider_index].height_value > colors[holding_slider_index-1].height_value {
          slice.swap(colors[:], holding_slider_index, holding_slider_index-1)
          holding_slider_index -= 1
          color_select_index -= 1
        }
        else if colors[holding_slider_index].height_value < colors[holding_slider_index+1].height_value {
          slice.swap(colors[:], holding_slider_index, holding_slider_index+1)
          holding_slider_index += 1
          color_select_index += 1
        }
      }
    }
    else do is_holding_color = false

    if hovering_new_color && rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
      new_height_value := min_max_normalization(rl.GetMousePosition().x, -10, 10, ui.start_position.x, ui.end_position.x)
      new_color := World_Color {
        height_value = new_height_value,
        color = rl.RED
      }

      append(&colors, new_color)

      new_color_index := len(colors) - 1
      outer: for i := new_color_index; i > 0; i -= 1 {
        if new_color.height_value < colors[i].height_value {
          slice.swap(colors[:], i, new_color_index)
          new_color_index -= 1
        }
        else {
          break outer
        }
      }
    }

    // Draw:
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)
    rl.DrawTexture(texture, 0, 0, rl.WHITE)

    rl.DrawLineV(ui.start_position, ui.end_position, ui.line_color)
    for i in 0..<len(colors) {
      circle_pos_x := min_max_normalization(colors[i].height_value, ui.start_position.x, ui.end_position.x, -10, 10)
      rl.DrawCircle(i32(circle_pos_x), i32(ui.start_position.y), ui.radius+ui.outline_thickness, rl.BLACK)
      rl.DrawCircle(i32(circle_pos_x), i32(ui.start_position.y), ui.radius, colors[i].color)
    }

    if selecting_color {
      position := rl.Vector2{
        min_max_normalization(
          colors[color_select_index].height_value,
          ui.start_position.x,
          ui.end_position.x,
          -10,
          10
        ) - 75/2,
        ui.start_position.y + ui.radius + ui.outline_thickness + 5,
      }

      rl.GuiColorPicker(
        rl.Rectangle{position.x, position.y, 75, 75},
        "picker",
        &colors[color_select_index].color
      )

      if rl.GuiButton(rl.Rectangle{position.x, position.y + 75, 75/2, 20}, "Copy") {
        color_cpy = colors[color_select_index].color
      }
      else if rl.GuiButton(rl.Rectangle{position.x + 75/2,  position.y + 75, 75/2, 20}, "Paste") {
        colors[color_select_index].color = color_cpy
      }
    }
    if hovering_new_color {
      rl.DrawCircleLinesV(rl.Vector2{rl.GetMousePosition().x, ui.start_position.y}, ui.radius, rl.GRAY)
    }

    // frequency and lacunarity sliders linked?
    octaves_f32 = f32(world.octaves)
    gui_custom_slider("octaves", rl.Rectangle{100, 200, 200, 15}, rl.ORANGE, 2, font, f32(font_size), &octaves_f32, 0, 5, 1)
    world.octaves = int(octaves_f32)

    gui_custom_slider("frequency", rl.Rectangle{100, 250, 200, 15}, rl.ORANGE, 2, font, f32(font_size), &world.frequency, 0, 0.005, 0.0002)
    gui_custom_slider("lacunarity", rl.Rectangle{100, 300, 200, 15}, rl.ORANGE, 2, font, f32(font_size), &world.lacunarity, 0, 5, 0.1)

    gui_custom_slider("persistence", rl.Rectangle{100, 350, 200, 15}, rl.ORANGE, 2, font, f32(font_size), &world.persistence, 0, 5, 0.1)
    gui_custom_slider("amplitude", rl.Rectangle{100, 400, 200, 15}, rl.ORANGE, 2, font, f32(font_size), &world.amplitude, 0, 5, 0.1)

    apply_mid_x := (ui.end_position.x - ui.start_position.x)/2 + ui.start_position.x - ui.width/2
    apply_mid_y := ui.start_position.y/2 - ui.height/2 - ui.radius/2
    if rl.GuiButton(rl.Rectangle{apply_mid_x, apply_mid_y, ui.width, ui.height}, "apply") {
      thread_pool: thread.Pool
      thread.pool_init(&thread_pool, context.allocator, WORKER_THREADS)

      for i in 0..<WORKER_THREADS {
        thread.pool_add_task(&thread_pool, context.allocator, worker, &data, i)
      }

      thread.pool_start(&thread_pool)
      thread.pool_finish(&thread_pool)

      rl.UnloadTexture(texture)
      texture = rl.LoadTextureFromImage(img)
      thread.pool_destroy(&thread_pool)
    }

    rl.DrawFPS(0, 0)
    rl.EndDrawing()
  }

  rl.UnloadTexture(texture)
  rl.CloseWindow()
}

worker :: proc(t: thread.Task) {
  data := cast(^Worker_Data)t.data
  world := data.world_data
  colors := data.color_data

  array_len := data.world_data.width_tiles * data.world_data.height_tiles
  per_task := world.height_tiles / WORKER_THREADS
  y_start := t.user_index*per_task
  y_end := (t.user_index+1)*per_task

  octaves_check := math.pow(2, f32(data.world_data.octaves))

  for x in 0..<world.width_tiles {
    for y in y_start..<y_end {
      i := (y * world.width_tiles + x)
      current_tile := data.heightmap_data[i]
      recalculate_tile(world^, &data.heightmap_data[i], octaves_check, noise.Vec2{f64(x), f64(y)})
      color := noise_to_color_lerp(colors, data.heightmap_data[i])
      data.pixel_data[i] = color
    }
  }
}

Worker_Data :: struct {
  heightmap_data: []f32,
  color_data: []World_Color,
  pixel_data: []rl.Color,
  world_data: ^World,
}

gui_custom_slider :: proc(
  text: string,
  bounding_box: rl.Rectangle,
  color: rl.Color,
  slider_outline: f32,
  font: rl.Font,
  font_size: f32,
  value: ^$T,
  min: T,
  max: T,
  step_size: T
) where intrinsics.type_is_float(T) {
  @static holding_slider: rawptr

  slider_position := min_max_normalization(value^, T(bounding_box.x), T(bounding_box.x + bounding_box.width), min, max)

  slider_rectangle := rl.Rectangle{
    f32(slider_position) - slider_outline,
    bounding_box.y - slider_outline,
    bounding_box.height + slider_outline*2,
    bounding_box.height + slider_outline*2
  }

  if rl.CheckCollisionPointRec(rl.GetMousePosition(), slider_rectangle) {
    if rl.IsMouseButtonDown(rl.MouseButton.LEFT){
      holding_slider = value
    }
  }
  if !rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
    holding_slider = nil
  }

  if holding_slider == value {
    value_before := value^
    value^ = math.clamp(min_max_normalization(
      T(rl.GetMousePosition().x - (bounding_box.height + slider_outline)/2),
      min,
      max,
      T(bounding_box.x),
      T(bounding_box.x + bounding_box.width),
    ), min, max)
    if math.abs(value_before - value^) < step_size {
      value^ = step_size + value_before
    }
  }

  rl.DrawLineV(
    rl.Vector2{bounding_box.x, bounding_box.y + bounding_box.height/2},
    rl.Vector2{bounding_box.x + bounding_box.width, bounding_box.y + bounding_box.height/2},
    rl.LIGHTGRAY
  )


  rl.DrawRectangleRec(
    slider_rectangle,
    rl.BLACK
  )
  rl.DrawRectangleRec(
    rl.Rectangle{f32(slider_position), bounding_box.y, bounding_box.height, bounding_box.height},
    color
  )

  rl.DrawTextEx(
    font,
    fmt.caprintf("%.5f", value^),
    rl.Vector2{bounding_box.x + bounding_box.width/2, bounding_box.y - bounding_box.height*1.25},
    font_size,
    0,
    rl.LIGHTGRAY
  )
  rl.DrawTextEx(
    font,
    fmt.caprintf(text),
    rl.Vector2{bounding_box.x, bounding_box.y - bounding_box.height*1.25},
    font_size,
    0,
    rl.LIGHTGRAY
  )
}
