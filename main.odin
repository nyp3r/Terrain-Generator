package main

import "core:slice/heap"
import "core:slice"
import "core:mem/virtual"
import "core:mem"
import "core:fmt"
import terrain "../TerrainTopDown"
import rl "vendor:raylib"
import imgui "./odin-imgui"
import imgui_rl "./imgui_impl_raylib"
import "core:math"
import "core:math/noise"
import "core:sync"
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

  timer: i64

  // ------------------------- threads --------------------------------------




  rl.SetTargetFPS(165)

  delta, last_time: f64

  for !rl.WindowShouldClose() {
    // ---------------------- imgui ---------------------------
    // Feed Raylib inputs to ImGui and start the frame
    imgui_rl.new_frame()
    imgui.NewFrame()

    // Create UI windows as normal
    imgui.Begin("Debug Window")

    imgui.InputDouble("frequency", &world.frequency, 0.0001, 0.0005)
    imgui.InputDouble("lacunarity", &world.lacunarity, 0.1, 0.5)
    imgui.DragInt("octaves", (^i32)(&world.octaves), 0.1, 2, 10, flags = imgui.SliderFlags{imgui.SliderFlag.NoSpeedTweaks})
    imgui.DragFloat("amplitude", &world.amplitude, 0.1, 0, 10)
    imgui.DragFloat("persistence", &world.persistence, 0.1, 0, 10)

    if imgui.Button("apply", imgui.Vec2{100, 20}) {
      timer_start := time.now()._nsec
      // tracks the threads
      wait_group: sync.Wait_Group

      // create threads
      thread1 := thread.create(worker)
      thread1.init_context = context
      thread1.user_index = 1
      thread1.data = &Worker_Data{
        wait_group = &wait_group,
        world_info = &world,
        heightmap_slice = heightmap[:len(heightmap)/2],
        pixels_slice = pixels[:len(pixels)/2],
        colors = colors,
        thread_number = 1,
      }

      thread2 := thread.create(worker)
      thread2.init_context = context
      thread2.user_index = 1
      thread2.data = &Worker_Data{
        wait_group = &wait_group,
        world_info = &world,
        heightmap_slice = heightmap[len(heightmap)/2:],
        pixels_slice = pixels[len(pixels)/2:],
        colors = colors,
        thread_number = 2,
      }

      // prepare for start of thread(s)
      sync.wait_group_add(&wait_group, 2)
      // start threads
      thread.start(thread1)
      thread.start(thread2)

      // if the threads are don working, the counter will be 0
      // then this will be called
      sync.wait_group_wait(&wait_group)

      // octaves_check := math.pow(f32(2), f32(world.octaves))
      //
      // for x in 0..<world.width_tiles {
      //   for y in 0..<world.height_tiles {
      //     i := (y * world.width_tiles + x)
      //     terrain.recalculate_tile(world, &heightmap[i], octaves_check, noise.Vec2{f64(x), f64(y)})
      //     color := terrain.noise_to_color_lerp(colors, heightmap[i])
      //     pixels[i] = color
      //   }
      // }
      rl.UnloadTexture(texture)
      texture = rl.LoadTextureFromImage(img)

      timer = time.now()._nsec - timer_start
   }

    imgui.Text(fmt.ctprintf("%d", timer))
    imgui.Text(fmt.ctprintf("%d", rl.GetFPS()))
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

worker :: proc(t: ^thread.Thread) {
  worker_data := cast(^Worker_Data)t.data
  world := worker_data.world_info
  colors := worker_data.colors

  octaves_check := math.pow(2, f32(worker_data.world_info.octaves))

  y_start := 0
  y_end := world.height_tiles

  switch(worker_data.thread_number){
    case 1:
      y_end = world.height_tiles/2

    case 2:
      y_start = world.height_tiles/2
  }

  for x in 0..<world.width_tiles {
    for y in y_start..<y_end {
      i := ((y - y_start) * world.width_tiles + x)

      current_tile := worker_data.heightmap_slice[i]
      terrain.recalculate_tile(world^, &worker_data.heightmap_slice[i], octaves_check, noise.Vec2{f64(x), f64(y)})
      color := terrain.noise_to_color_lerp(colors, worker_data.heightmap_slice[i])
      r := color.r
      g := color.g
      b := color.b
      a := color.a
      worker_data.pixels_slice[i] = color
    }
  }

  fmt.println("thread", worker_data.thread_number, "is done")
  sync.wait_group_done(worker_data.wait_group)
}

Worker_Data :: struct {
  heightmap_slice: []f32,
  colors: []terrain.World_Color,
  pixels_slice: []rl.Color,

  wait_group: ^sync.Wait_Group,

  thread_number: int,
  world_info: ^terrain.World,
}
