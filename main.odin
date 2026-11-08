package main

import "core:slice"
import "core:mem"
import "core:fmt"
import terrain "../TerrainTopDown"
import rl "vendor:raylib"
import "core:math"
import "core:math/noise"
import "core:thread"

WORKER_THREADS :: 8

UI_Values :: struct {
  size: f32,
  start_position: rl.Vector2,
  slider_size_multiplier: f32,
  slider_length: f32,
}

main :: proc() {

  world := terrain.World {
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

  colors: [dynamic]terrain.World_Color
  append(&colors, terrain.World_Color{99999, rl.WHITE})
  append(&colors, terrain.World_Color{10, rl.WHITE})
  append(&colors, terrain.World_Color{3, rl.GRAY})
  append(&colors, terrain.World_Color{2, rl.Color{0, 180, 0, 255}})
  append(&colors, terrain.World_Color{0, rl.Color{0, 200, 0, 255}})
  append(&colors, terrain.World_Color{-1, rl.Color{0, 180, 0, 255}})
  append(&colors, terrain.World_Color{-4, rl.Color{0, 200, 0, 255}})
  append(&colors, terrain.World_Color{-6, rl.BLUE})
  append(&colors, terrain.World_Color{-10, rl.DARKBLUE})
  append(&colors, terrain.World_Color{-99999, rl.DARKBLUE})

  rl.InitWindow(i32(world.width_tiles*world.tile_size), i32(world.height_tiles*world.tile_size), "Raylib")


  heightmap := terrain.make_heightmap(world.width_tiles, world.height_tiles)
  terrain.populate_heightmap(world, &heightmap)

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
      color := terrain.noise_to_color_lerp(colors[:], heightmap[i])
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

  ui_style := UI_Values{
    size = 30,
    start_position = rl.Vector2{100, 100},
    slider_size_multiplier = 0.75,
    slider_length = 100,
  }
  holding_slider_index: int
  is_holding_slider := false
  selecting_color := false
  color_select_index: int

  timer: i64
  delta, last_time: f64

  // TODO:
  // * proper UI placements
  // * adding more colors
  // * UI for changing algorithm values
  //
  // TODO: future ideas
  // * additional simplex noise for ores or similar

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
    color_select: for i in 0..<len(colors) {
      circle_pos_x := terrain.min_max_normalization(100, 800, -10, 10, colors[i].height_value)
      if rl.IsMouseButtonDown(rl.MouseButton.RIGHT) && rl.CheckCollisionPointCircle(rl.GetMousePosition(), rl.Vector2{circle_pos_x, 100}, 13) {
        selecting_color = true
        color_select_index = i
        break color_select
      }
    }

    // Dragging sliders
    if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
      if !is_holding_slider {
        height_value: for i in 0..<len(colors) {
          circle_pos_x := terrain.min_max_normalization(100, 800, -10, 10, colors[i].height_value)
          if rl.IsMouseButtonDown(rl.MouseButton.LEFT) && rl.CheckCollisionPointCircle(rl.GetMousePosition(), rl.Vector2{circle_pos_x, 100}, 13) {
            is_holding_slider = true
            holding_slider_index = i
            break height_value
          }
        }
      }
      else {
        colors[holding_slider_index].height_value = math.clamp(terrain.min_max_normalization(-10, 10, 100, 800, rl.GetMousePosition().x), -10, 10)
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
    else do is_holding_slider = false


    // Draw:
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)
    rl.DrawTexture(texture, 0, 0, rl.WHITE)

    rl.DrawLine(100, 100, 800, 100, rl.RED)
    for i in 0..<len(colors) {
      circle_pos_x := terrain.min_max_normalization(100, 800, -10, 10, colors[i].height_value)
      rl.DrawCircle(i32(circle_pos_x), 100, 13, rl.BLACK)
      rl.DrawCircle(i32(circle_pos_x), 100, 10, colors[i].color)
    }

    if selecting_color {
      rl.GuiColorPicker(rl.Rectangle{100, 200, 75, 75}, "picker", &colors[color_select_index].color)
    }

    if rl.GuiButton(rl.Rectangle{20, 20, 50, 20}, "apply") {
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
      terrain.recalculate_tile(world^, &data.heightmap_data[i], octaves_check, noise.Vec2{f64(x), f64(y)})
      color := terrain.noise_to_color_lerp(colors, data.heightmap_data[i])
      data.pixel_data[i] = color
    }
  }
}

Worker_Data :: struct {
  heightmap_data: []f32,
  color_data: []terrain.World_Color,
  pixel_data: []rl.Color,
  world_data: ^terrain.World,
}

draw_ui :: proc(ui_style: UI_Values, colors: []terrain.World_Color) {
  @static color_picker_index: int
  rl.DrawRectangle(
    i32(ui_style.start_position.x) - i32(ui_style.size / 2),
    i32(ui_style.start_position.x) - i32(ui_style.size / 2),
    i32(ui_style.size) * 2 + i32(ui_style.slider_length + ui_style.size + ui_style.size/2),
    i32(ui_style.size + ui_style.size/2) * i32(len(colors)) + i32(ui_style.size / 2),
    rl.BLACK
  )
  for i in 0..<len(colors) {

    if rl.GuiButton(
      rl.Rectangle{
        ui_style.start_position.x,
        ui_style.start_position.x + f32(ui_style.size + ui_style.size/2) * f32(i),
        ui_style.size, 
        ui_style.size
      },
      "color"
    ) {
      color_picker_index = i
    }

    rl.DrawRectangleRec(
      rl.Rectangle{
        ui_style.start_position.x,
        ui_style.start_position.x + f32(ui_style.size + ui_style.size/2) * f32(i),
        ui_style.size,
        ui_style.size
      },
      colors[i].color
    )

    rl.GuiSlider(
      rl.Rectangle{
        ui_style.start_position.x + ui_style.size*2,
        ui_style.start_position.y + f32(ui_style.size + ui_style.size/2) * f32(i),
        ui_style.slider_length,
        ui_style.size * ui_style.slider_size_multiplier
      }, 
      "-10",
      "10",
      &colors[i].height_value,
      -10,
      10
    )
    if i == len(colors)-1 {
      colors[i].height_value = math.min(colors[i].height_value, colors[i-1].height_value)
    }
    else if i == 0 {
      colors[i].height_value = math.max(colors[i].height_value, colors[i+1].height_value)
    }
    else {
      colors[i].height_value = math.clamp(colors[i].height_value, colors[i+1].height_value, colors[i-1].height_value)
    }

    rl.GuiLabel(
      rl.Rectangle{
        ui_style.start_position.x + ui_style.size*2,
        ui_style.start_position.y + f32(ui_style.size + ui_style.size/2) * f32(i) - f32(ui_style.size/1.5),
        100,
        ui_style.size * ui_style.slider_size_multiplier
      },
      fmt.ctprintf("%0.2f", colors[i].height_value)
    )
  }

  rl.GuiColorPicker(
    rl.Rectangle{
      ui_style.start_position.x + ui_style.size + ui_style.size/2 + ui_style.slider_length + ui_style.size,
      ui_style.start_position.x + (ui_style.size + ui_style.size/2) * f32(color_picker_index) + ui_style.size/2,
      ui_style.size*4,
      ui_style.size*4
    },
    "color picker",
    &colors[color_picker_index].color
  )
}
