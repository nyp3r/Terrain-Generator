package main

import "core:slice"
import "core:mem"
import "core:fmt"
import terrain "../TerrainTopDown"
import rl "vendor:raylib"
import imgui "./odin-imgui"
import imgui_rl "./imgui_impl_raylib"
import "core:math"
import "core:math/noise"
import "core:thread"
import "core:time"

WORKER_THREADS :: 8

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

  colors := []terrain.World_Color {
    terrain.World_Color {
      height_value = 9999,
      color = rl.WHITE
    },
    terrain.World_Color {
      height_value = 12,
      color = rl.WHITE
    },
    terrain.World_Color {
      height_value = 11,
      color = rl.WHITE
    },
    terrain.World_Color {
      height_value = 3,
      color = rl.GRAY
    },
    terrain.World_Color {
      height_value = 2,
      color = rl.Color{0, 180, 0, 255}
    },
    terrain.World_Color {
      height_value = 0,
      color = rl.Color{0, 200, 0, 255}
    },
    terrain.World_Color {
      height_value = -1,
      color = rl.Color{0, 200, 0, 255}
    },
    terrain.World_Color {
      height_value = -4,
      color = rl.Color{0, 180, 0, 255}
    },
    terrain.World_Color {
      height_value = -5,
      color = rl.BLUE
    },
    terrain.World_Color {
      height_value = -10,
      color = rl.DARKBLUE
    },
    terrain.World_Color {
      height_value = -9999,
      color = rl.DARKBLUE
    },
  }


  rl.InitWindow(i32(world.width_tiles*world.tile_size), i32(world.height_tiles*world.tile_size), "Raylib")


  // ---------------------- imgui ---------------------------
  // Initialize core ImGui
  imgui.CreateContext(nil)
  defer imgui.DestroyContext(nil)

  // Initialize the Raylib-specific bridge
  imgui_rl.init()
  defer imgui_rl.shutdown()
  // ---------------------- imgui ---------------------------



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
      color := terrain.noise_to_color_lerp(colors, heightmap[i])
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


  // ------------------------- threads --------------------------------------

  data := Worker_Data{
    world_data = &world,
    heightmap_data = heightmap,
    pixel_data = pixels,
    color_data = colors,
  }


  // thread.pool_add_task(&thread_pool, context.allocator, worker, &data, 0)

  // ------------------------- threads --------------------------------------




  rl.SetTargetFPS(165)

  timer: i64
  delta, last_time: f64

  for !rl.WindowShouldClose() {
    // ---------------------- imgui ---------------------------
    // Feed Raylib inputs to ImGui and start the frame
    imgui_rl.new_frame()
    imgui.NewFrame()

    rl_color_to_f32_color :: proc(rl_color: rl.Color) -> (return_color: [4]f32) {
      for i in 0..<4 {
        return_color[i] = 1.0 / f32(rl_color[i])
      }
      return
    }

    // Create UI windows as normal
    imgui.Begin("editor", flags=imgui.WindowFlags{imgui.WindowFlag.NoCollapse})

    imgui.InputDouble("frequency", &world.frequency, 0.0001, 0.0005)
    imgui.InputDouble("lacunarity", &world.lacunarity, 0.1, 0.5)
    imgui.DragInt("octaves", (^i32)(&world.octaves), 0.1, 2, 10, flags = imgui.SliderFlags{imgui.SliderFlag.NoSpeedTweaks})
    imgui.DragFloat("amplitude", &world.amplitude, 0.1, 0, 10)
    imgui.DragFloat("persistence", &world.persistence, 0.1, 0, 10)

    imgui.BeginChild("colors", 
      child_flags=imgui.ChildFlags{
        imgui.ChildFlag.Borders, 
        imgui.ChildFlag.AlwaysUseWindowPadding
      }
    )
    for &color, i in colors {
      id := fmt.ctprintf("%d", color.height_value)
      imgui.PushID(id)
      // TODO:
      // imgui.ColorEdit4(id, rl_color_to_f32_color(color.color))
      imgui.InputFloat("height", &color.height_value)
      imgui.PopID()
    }
    imgui.EndChild()

    if imgui.Button("apply", imgui.Vec2{100, 20}) {
      timer_start := time.now()._nsec

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

      timer = time.now()._nsec - timer_start
   }

    imgui.Text(fmt.ctprintf("timer(ms): %d", timer/1000_000))
    imgui.Text(fmt.ctprintf("FPS: %d", rl.GetFPS()))
    imgui.End()

    imgui.Render()
    // ---------------------- imgui ---------------------------


    // Update:
    delta = rl.GetTime() - last_time
    last_time = rl.GetTime()

    if rl.IsKeyPressed(rl.KeyboardKey.Q) {
      rl.CloseWindow()
    }

    // Draw:
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)


    // if slider is used... change texture

    rl.DrawTexture(texture, 0, 0, rl.WHITE)

    rl.DrawFPS(0, 0)
    // imgui
    imgui_rl.render_draw_data(imgui.GetDrawData())
    // imgui

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
