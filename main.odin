package main

import "base:intrinsics"
import "core:slice"
import "core:mem"
import "core:fmt"
import rl "vendor:raylib"
import "core:math"
import "core:math/noise"
import "core:thread"
import "core:strings"
import "core:strconv"

WORKER_THREADS :: 8

UI_ :: struct {
  // "color circles"
  color_slider_radius: f32,
  color_slider_outline_thickness: f32,

  // slider
  colors_start_pos: rl.Vector2,
  colors_end_pos: rl.Vector2,

  // apply button
  apply_width: f32,
  apply_height: f32,

  // line
  line_color: rl.Color,

  // algorithm values
  algorithm_values_rec: rl.Rectangle,
  algorithm_values_margin: f32,
  algorithm_values_spacing: f32,
}

UI_Group :: struct {
  // basic
  position: rl.Vector2,
  size: rl.Vector2,

  background_color: rl.Color,
  padding: f32,
  spacing: f32,
  outline_thickness: f32,
  outline_color: rl.Color,
  font: rl.Font,

  // extra
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
  append(&colors, World_Color{0, rl.Color{0, 180, 0, 255}})
  append(&colors, World_Color{-1, rl.Color{0, 200, 0, 255}})
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
  color_picker_pos: rl.Vector2
  color_picker_rec := rl.Rectangle{color_picker_pos.x, color_picker_pos.y, 75, 75}

  octaves_f32: f32

  ui := UI_ {
    color_slider_radius = 10,
    color_slider_outline_thickness = 2,

    colors_start_pos = rl.Vector2{100,100},
    colors_end_pos = rl.Vector2{f32(world.width_tiles) - 100, 100},

    apply_width = 100,
    apply_height = 30,

    line_color = rl.LIGHTGRAY,

    algorithm_values_rec = rl.Rectangle{100, 150, 225, 310},
    algorithm_values_margin = 25,
    algorithm_values_spacing = 50,
  }

  timer: i64
  delta, last_time: f64

  // TODO:
  // * move/minimize UI
  // * show height value at cursor when hovering map
  // * stop showing color picker when you click away

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

  colors_ui := UI_Group {
    position = {100,600},
    size = {f32(world.width_tiles - 200), 20},
    outline_thickness = 1,
    outline_color = rl.BLACK,
    background_color = {0, 0, 0, 0},
    padding = 0,

    font = rl.LoadFontEx(
      "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf",
      font_size,
      code_points,
      code_point_count
    ),
    line_color = rl.LIGHTGRAY,
  }

  for !rl.WindowShouldClose() {
    // Update:
    delta = rl.GetTime() - last_time
    last_time = rl.GetTime()

    if rl.IsKeyPressed(rl.KeyboardKey.Q) {
      rl.CloseWindow()
    }

    // Picking colors
    if (rl.IsMouseButtonPressed(rl.MouseButton.LEFT) || rl.IsMouseButtonPressed(rl.MouseButton.RIGHT)) && !rl.CheckCollisionPointRec(rl.GetMousePosition(), color_picker_rec) {
      selecting_color = false
    }

    if rl.GetMousePosition().y < ui.colors_start_pos.y + ui.color_slider_radius + ui.color_slider_outline_thickness && rl.GetMousePosition().y > ui.colors_start_pos.y || 
    rl.GetMousePosition().y > ui.colors_start_pos.y - ui.color_slider_radius - ui.color_slider_outline_thickness && rl.GetMousePosition().y < ui.colors_start_pos.y {
      hovering_new_color = true

      height_value: for i in 0..<len(colors) {
        circle_pos_x := min_max_normalization(colors[i].height_value, ui.colors_start_pos.x, ui.colors_end_pos.x, -10, 10)

        if rl.CheckCollisionPointCircle(
          rl.GetMousePosition(),
          rl.Vector2{circle_pos_x, ui.colors_start_pos.y},
          ui.color_slider_radius + ui.color_slider_outline_thickness
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
            color_picker_pos = rl.Vector2{
              min_max_normalization(
                colors[color_select_index].height_value,
                ui.colors_start_pos.x,
                ui.colors_end_pos.x,
                -10,
                10
              ) - 75/2,
              ui.colors_start_pos.y + ui.color_slider_radius + ui.color_slider_outline_thickness + 5,
            }
            color_picker_rec = {color_picker_pos.x, color_picker_pos.y, color_picker_rec.width, color_picker_rec.height}
            color_select_index = i
          }
        }
      }
    }
    else do hovering_new_color = false

    if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
      // Dragging colors
      if is_holding_color {
        colors[holding_slider_index].height_value = math.clamp(min_max_normalization(rl.GetMousePosition().x, -10, 10, ui.colors_start_pos.x, ui.colors_end_pos.x), -10, 10)
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
      new_height_value := min_max_normalization(rl.GetMousePosition().x, -10, 10, ui.colors_start_pos.x, ui.colors_end_pos.x)
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

    rl.DrawLineV(ui.colors_start_pos, ui.colors_end_pos, ui.line_color)
    for i in 0..<len(colors) {
      circle_pos_x := min_max_normalization(colors[i].height_value, ui.colors_start_pos.x, ui.colors_end_pos.x, -10, 10)
      rl.DrawCircle(i32(circle_pos_x), i32(ui.colors_start_pos.y), ui.color_slider_radius+ui.color_slider_outline_thickness, rl.BLACK)
      rl.DrawCircle(i32(circle_pos_x), i32(ui.colors_start_pos.y), ui.color_slider_radius, colors[i].color)
    }

    if hovering_new_color {
      rl.DrawCircleLinesV(rl.Vector2{rl.GetMousePosition().x, ui.colors_start_pos.y}, ui.color_slider_radius, rl.GRAY)
    }

    rl.DrawRectangleV(
      rl.Vector2{
        ui.algorithm_values_rec.x - ui.algorithm_values_margin,
        ui.algorithm_values_rec.y - ui.algorithm_values_margin - f32(font.baseSize)
      },
      rl.Vector2{
        ui.algorithm_values_rec.width + ui.algorithm_values_margin*2,
        ui.algorithm_values_rec.height + ui.algorithm_values_margin*2
      },
      rl.Color{0, 0, 0, 100}
    )

    gui_colors_slider(colors_ui, &colors, 75)

    gui_number_input(rl.Vector2{ui.algorithm_values_rec.x, ui.algorithm_values_rec.y}, 200, font, "seed", &world.seed)

    octaves_f32 = f32(world.octaves)
    gui_custom_slider("octaves", rl.Rectangle{
      ui.algorithm_values_rec.x,
      ui.algorithm_values_rec.y + ui.algorithm_values_spacing,
      200,
      15
    }, rl.ORANGE, ui.line_color, 2, font, f32(font_size), &octaves_f32, 0, 5, 1, 0)
    world.octaves = int(octaves_f32)

    gui_custom_slider(
      "frequency",
      rl.Rectangle{
        ui.algorithm_values_rec.x,
        ui.algorithm_values_rec.y + ui.algorithm_values_spacing*2,
        200,
        15
      },
      rl.ORANGE, ui.line_color, 2, font, f32(font_size), &world.frequency, 0, 0.005, 0.0002, 4
    )

    gui_custom_slider(
      "lacunarity",
      rl.Rectangle{
        ui.algorithm_values_rec.x,
        ui.algorithm_values_rec.y + ui.algorithm_values_spacing*3,
        200,
        15
      },
      rl.ORANGE, ui.line_color, 2, font, f32(font_size), &world.lacunarity, 0, 5, 0.1, 1
    )

    gui_custom_slider(
      "persistence",
      rl.Rectangle{
        100,
        350,
        200,
        15
      },
      rl.ORANGE, ui.line_color, 2, font, f32(font_size), &world.persistence, 0, 5, 0.1, 1
    )
    gui_custom_slider("amplitude",
      rl.Rectangle{
        100,
        400,
        200,
        15
      },
      rl.ORANGE, ui.line_color, 2, font, f32(font_size), &world.amplitude, 0, 5, 0.1, 1
    )

    apply_mid_x := (ui.colors_end_pos.x - ui.colors_start_pos.x)/2 + ui.colors_start_pos.x - ui.apply_width/2
    apply_mid_y := ui.colors_start_pos.y/2 - ui.apply_height/2 - ui.color_slider_radius/2
    if rl.GuiButton(rl.Rectangle{apply_mid_x, apply_mid_y, ui.apply_width, ui.apply_height}, "apply") || rl.IsKeyPressed(rl.KeyboardKey.KP_ENTER) {
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

    if selecting_color {

      rl.GuiColorPicker(
        color_picker_rec,
        "picker",
        &colors[color_select_index].color
      )

      if rl.GuiButton(rl.Rectangle{color_picker_pos.x, color_picker_pos.y + 75, 75/2, 20}, "Copy") {
        color_cpy = colors[color_select_index].color
      }
      else if rl.GuiButton(rl.Rectangle{color_picker_pos.x + 75/2,  color_picker_pos.y + 75, 75/2, 20}, "Paste") {
        colors[color_select_index].color = color_cpy
      }
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
  line_color: rl.Color,
  slider_outline: f32,
  font: rl.Font,
  font_size: f32,
  value: ^$T,
  min: T,
  max: T,
  step_size: T,
  decimal_places: int,
) where intrinsics.type_is_float(T) {
  @static holding_slider: rawptr

  slider_position := min_max_normalization(value^, T(bounding_box.x), T(bounding_box.x + bounding_box.width), min, max)

  slider_rectangle := rl.Rectangle{
    f32(slider_position) - slider_outline - (bounding_box.height + slider_outline)/2,
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

  // NOTE: slow movement and misaligned "point of change"
  if holding_slider == value {
    new_value := math.clamp(min_max_normalization(
      T(rl.GetMousePosition().x - (bounding_box.height + slider_outline)),
      min,
      max,
      T(bounding_box.x - (bounding_box.height + slider_outline)),
      T(bounding_box.x + bounding_box.width - (bounding_box.height + slider_outline)),
    ), min, max)
    if new_value - value^ >= step_size {
      // multiplying to instantly set it to the correct value
      value^ += step_size
    }
    else if value^ - new_value >= step_size {
      value^ -= step_size
    }
  }

  rl.DrawLineV(
    rl.Vector2{bounding_box.x, bounding_box.y + bounding_box.height/2},
    rl.Vector2{bounding_box.x + bounding_box.width, bounding_box.y + bounding_box.height/2},
    line_color
  )


  rl.DrawRectangleRec(
    slider_rectangle,
    rl.BLACK
  )
  rl.DrawRectangleRec(
    rl.Rectangle{slider_rectangle.x + slider_outline, bounding_box.y, bounding_box.height, bounding_box.height},
    color
  )

  decimal_formatting := fmt.aprintf("%%.%df", decimal_places)
  rl.DrawTextEx(
    font,
    fmt.caprintf(decimal_formatting, value^),
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

gui_number_input :: proc(
  position: rl.Vector2,
  length: f32,
  font: rl.Font,
  text: cstring,
  value: ^i64
) {
  padding := f32(2)
  hovering := false
  @static input: [dynamic]string

  text_box := rl.Rectangle{
    position.x - padding,
    position.y - padding,
    length + padding*2,
    f32(font.baseSize) + padding*2
  }
  if rl.CheckCollisionPointRec(rl.GetMousePosition(), text_box) {
    rl.SetMouseCursor(rl.MouseCursor.IBEAM)
    hovering = true
  }
  else {
    rl.SetMouseCursor(rl.MouseCursor.DEFAULT)
    hovering = false
  }

  if hovering {
    // NOTE: can't hold key | do normal focus with inline cursor?
    if key := rl.GetKeyPressed(); key != rl.KeyboardKey.KEY_NULL {
      // keys 48 - 57 are top row numbers | keys 320 - 329 are from the keypad
      if (i32(key) >= 48 && i32(key) <= 57) || (i32(key) >= 320 && i32(key) <= 329) {
        append(&input, strings.clone_from_cstring(rl.GetKeyName(key)))
      }
      else if key == rl.KeyboardKey.BACKSPACE && len(input) > 0 {
        pop(&input)
      }
    }
  }

  rl.DrawRectangleRec(text_box, rl.WHITE)
  if len(input) > 0 {
    input_string := strings.concatenate(input[:])
    ok: bool
    value^, ok = strconv.parse_i64(input_string)
    rl.DrawTextEx(font, strings.clone_to_cstring(input_string), position, f32(font.baseSize), 0, rl.BLACK)
  }
  rl.DrawTextEx(font, text, rl.Vector2{position.x, position.y - text_box.height}, f32(font.baseSize), 0, rl.WHITE)
}

gui_colors_slider :: proc(ui: UI_Group, colors: ^[dynamic]World_Color, color_picker_size: f32) {
  line_y := ui.position.y + ui.size.y/2
  circle_radius := ui.size.y/2
  line_start := rl.Vector2{ui.position.x + ui.padding + circle_radius, line_y}
  line_end := rl.Vector2{ui.position.x - ui.padding + ui.size.x - circle_radius, line_y}
  hovering_circle := false
  @static is_holding_circle := false
  @static selecting_color := false
  @static interacted_circle_index := 0
  @static color_picker_pos: rl.Vector2
  mouse_position := rl.GetMousePosition()

  if rl.CheckCollisionPointRec(mouse_position, {ui.position.x, ui.position.y, ui.size.x, ui.size.y}) {

    for i in 0..<len(colors){
      color_pos_x := min_max_normalization(colors[i].height_value, line_start.x, line_end.x, -10, 10)
      
      if rl.CheckCollisionPointCircle(mouse_position, {color_pos_x, line_y}, circle_radius) {
        hovering_circle = true
      }
      if !is_holding_circle &&
      rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
        // start holding color
        is_holding_circle = true
        interacted_circle_index = i
      }
      else if rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) && rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) {
        // remove color on shift + right click
        ordered_remove(colors, i)
      }
      else if rl.IsMouseButtonDown(rl.MouseButton.RIGHT) {
        // change color on right click

        selecting_color = true
        color_picker_pos = rl.Vector2{
          min_max_normalization(
            colors[interacted_circle_index].height_value,
            line_start.x,
            line_end.x,
            -10,
            10
          ) - color_picker_size/2,
          line_y + circle_radius + 5,
        }
      }
    }
  }


  if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
    // Dragging colors
    if is_holding_circle {
      colors[interacted_circle_index].height_value = math.clamp(
        min_max_normalization(
          rl.GetMousePosition().x,
          -10,
          10,
          line_start.x,
          line_end.x,
        ),
        -10,
        10
      )

      if colors[interacted_circle_index].height_value > colors[interacted_circle_index-1].height_value {
        slice.swap(colors[:], interacted_circle_index, interacted_circle_index-1)
        interacted_circle_index -= 1
      }
      else if colors[interacted_circle_index].height_value < colors[interacted_circle_index+1].height_value {
        slice.swap(colors[:], interacted_circle_index, interacted_circle_index+1)
        interacted_circle_index += 1
      }
    }
  }
  else do is_holding_circle = false

  // TODO: finish this
  if !hovering_circle && rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
    new_height_value := min_max_normalization(rl.GetMousePosition().x,
      -10,
      10,
      ui.colors_start_pos.x,
      ui.colors_end_pos.x)
    new_color := World_Color {
      height_value = new_height_value,
      color = rl.RED
    }

    append(colors, new_color)

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

  // draw
  rl.DrawRectangleV(ui.position, ui.size, ui.background_color)
  rl.DrawLineV(line_start, line_end, ui.line_color)
  for &color in colors {
    color_pos_x := min_max_normalization(color.height_value, line_start.x, line_end.x, -10, 10)

    rl.DrawCircleV(
      rl.Vector2{
        color_pos_x,
        line_y,
      },
      ui.size.y/2 - ui.padding*2,
      ui.outline_color,
    )

    rl.DrawCircleV(
      rl.Vector2{
        color_pos_x,
        line_y,
      },
      ui.size.y/2 - ui.outline_thickness*2 - ui.padding*2,
      color.color,
    )
  }
}
