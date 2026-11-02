package main

import "core:fmt"
import terrain "../TerrainTopDown"
import rl "vendor:raylib"
import imgui "./odin-imgui"
import imgui_rl "./imgui_impl_raylib"
import "core:math"
import "core:math/noise"
import "core:sync"
import "core:thread"

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
  alloc_size := u32(world.height_tiles * world.width_tiles * size_of(rl.Color))
  pixels := ([^]rl.Color)(rl.MemAlloc(alloc_size))
  defer rl.MemFreePtr(rawptr(pixels))

  for x in 0..<world.width_tiles {
    for y in 0..<world.height_tiles {
      i := (y * world.width_tiles + x)
      color := terrain.noise_to_color_lerp(colors, heightmap[i])
      pixels[i] = color
    }
  }

  img := rl.Image {
    data = rawptr(pixels),
    width = i32(world.width_tiles) * i32(world.tile_size),
    height = i32(world.height_tiles) * i32(world.tile_size),
    mipmaps = 1,
    format = rl.PixelFormat.UNCOMPRESSED_R8G8B8A8,
  }
  texture := rl.LoadTextureFromImage(img)
  // ------------------------------------------------------------------------







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

      octaves_check := math.pow(f32(2), f32(world.octaves))

      terrain.populate_heightmap(world, &heightmap)
      for x in 0..<world.width_tiles {
        for y in 0..<world.height_tiles {
          i := (y * world.width_tiles + x)
          terrain.recalculate_tile(world, &heightmap[i], octaves_check, noise.Vec2{f64(x), f64(y)})
          color := terrain.noise_to_color_lerp(colors, heightmap[i])
          pixels[i] = color
        }
      }
      rl.UnloadTexture(texture)
      texture = rl.LoadTextureFromImage(img)
    }

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
