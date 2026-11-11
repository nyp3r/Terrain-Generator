package main

import "base:intrinsics"
import "core:math/noise"
import math "core:math"
import rl "vendor:raylib"

World :: struct {
  // tiles
  width_tiles: int,
  height_tiles: int,
  tile_size: int,

  // terrain
  seed: i64,
  frequency: f64,
  octaves: int,
  lacunarity: f64,
  persistence: f32,
  amplitude: f32,
}

World_Color :: struct {
  height_value: f32,
  color: rl.Color,
}

index_to_coordinates_raylib :: proc(
	i: int,
  world: World
) -> (
	coordinates: rl.Vector2,
) {
	coordinates.x = f32(i % world.width_tiles) * f32(world.tile_size)
	coordinates.y =
		f32((i / world.width_tiles) % world.height_tiles) *
		f32(world.tile_size)
	return
}

index_to_coordinates_noise :: proc(
	i: int,
  world: World
) -> (
	coordinates: noise.Vec2,
) {
	coordinates.x = f64(i % world.width_tiles) * f64(world.tile_size)
	coordinates.y =
		f64((i / world.width_tiles) % world.height_tiles) *
		f64(world.tile_size)
	return
}

noise_to_gray_scale_color :: proc(noise: f32) -> rl.Color {
  return rl.ColorBrightness(rl.Color{127, 127, 127, 255}, noise)
}

min_max_normalization :: proc(x: $T, a, b, min_x, max_x: T) -> T where intrinsics.type_is_float(T) {
  numerator := (x - min_x) * (b - a)
  denominator := max_x - min_x
  return a + numerator / denominator
}

make_heightmap :: proc(width, height: int, allocator := context.allocator) -> (heightmap: []f32) {
	heightmap = make([]f32, width * height, allocator)
	return
}

populate_heightmap :: proc(world: World, heightmap: ^[]f32) {
  octaves_check := math.pow(f32(2), f32(world.octaves))

  for i in 0..<len(heightmap) {
    recalculate_tile(world, &heightmap[i], octaves_check, index_to_coordinates_noise(i, world))
  }
}
recalculate_tile :: proc(world: World, tile: ^f32, octaves_check: f32, coordinate: noise.Vec2) {
  tile^ = noise.noise_2d(world.seed, coordinate * world.frequency)

  for oct := 2; f32(oct) < octaves_check; oct *= 2 {
    tile^ += (noise.noise_2d(world.seed,
      coordinate *
      world.frequency *
      world.lacunarity *
      f64(oct)
    ) / f32(oct)) *
    world.amplitude *
    world.persistence *
    f32(oct)
  }
}

noise_to_color_lerp :: proc(colors: []World_Color, value: f32) -> rl.Color {
  higher_color, lower_color: World_Color
  for i in 0..<len(colors) {
    if value < colors[i].height_value {
      higher_color = colors[i]
      if i < len(colors)-1 {
        lower_color = colors[i+1]
      }
      else {
        lower_color = World_Color{value - 0.1,rl.BLACK}
      }
    }
  }
  normalized_value := 
    min_max_normalization(
      value,
      f32(0),
      f32(1),
      lower_color.height_value,
      higher_color.height_value,
    )
  return rl.ColorLerp(
    lower_color.color,

    higher_color.color,
    normalized_value
  )

  // TODO: ideas:
  // brightness transitions
  // transition between colors in one 'World_Color'
  // color differently when it's flat and when value changes quickly fx. green grass at flat areas and gray rocks at steep areas
}

noise_to_color_flatness :: proc(tile_area: [9]f32, colors: []World_Color) -> rl.Color {
  value := tile_area[5]
  tile_area_flatness := tile_area - value

  for i in 0..<9 {
    if i == 5 do continue

    if tile_area_flatness[i] > 0.005 && tile_area[i] > -0.5{
      return noise_to_color_lerp(colors, value)
    }
  }

  return rl.GREEN
}
