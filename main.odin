package main

import "core:fmt"
import terrain "../TerrainTopDown"
import rl "vendor:raylib"
import imgui "./odin-imgui"
import imgui_rl "./imgui_impl_raylib"

main :: proc() {

  world := terrain.World {
    width_tiles = 1280,
    height_tiles = 720,
    tile_size = 1,

    seed = 1012,
    frequency = 0.002,
    octaves = 2,
    lacunarity = 0.5,
    amplitude = 6,
    persistence = 1.0,
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

  rl.SetTargetFPS(165)
  
  delta, last_time: f64

  for(!rl.WindowShouldClose()){
    // ---------------------- imgui ---------------------------
    // Feed Raylib inputs to ImGui and start the frame
    imgui_rl.new_frame()
    imgui.NewFrame()

    // Create UI windows as normal
    imgui.Begin("Debug Window")
    imgui.DragFloat("frequency", &world.amplitude, 0.1, 0, 10)
    imgui.Text(fmt.ctprintf("%d", rl.GetFPS()))
    imgui.End()

    imgui.Render()
    // ---------------------- imgui ---------------------------


    // Update:
    delta = rl.GetTime() - last_time
    last_time = rl.GetTime()

    // Draw:
    rl.BeginDrawing()
    rl.ClearBackground(rl.WHITE)

    for i in 0..<len(heightmap) {
      rl.DrawRectangleV(
        terrain.index_to_coordinates_raylib(i, world),
        rl.Vector2(1) * f32(world.tile_size),
        terrain.noise_to_color_lerp(colors, heightmap[i])
      )
    }

    // imgui
    imgui_rl.render_draw_data(imgui.GetDrawData())
    // imgui

    rl.EndDrawing()
  }

  rl.CloseWindow()
}
