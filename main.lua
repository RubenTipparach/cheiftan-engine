-- Main entry point with scene manager
local scene_manager = require("scene_manager")

-- Register all scenes
scene_manager.register("menu", require("menu"))
scene_manager.register("test_cube", require("test_cube_scene"))
scene_manager.register("city", require("city_scene"))
scene_manager.register("cubes_dda", require("cubes_scene_dda"))
scene_manager.register("fog", require("fog_scene"))
scene_manager.register("lighting", require("lighting_test_scene"))

function love.load()
    -- Window mode is set in conf.lua
    -- Start with menu
    scene_manager.switch("menu")
end

function love.update(dt)
    scene_manager.update(dt)
end

function love.draw()
    scene_manager.draw()
end

function love.keypressed(key)
    scene_manager.keypressed(key)
end
