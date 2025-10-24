-- Centralized engine configuration
-- Change resolution here to affect all scenes

local config = {}

-- Render resolution (software renderer resolution)
config.RENDER_WIDTH = 480
config.RENDER_HEIGHT = 270

-- Window resolution (actual window size)
config.WINDOW_WIDTH = 960
config.WINDOW_HEIGHT = 540

-- Renderer settings
config.NEAR_PLANE = 0.01
config.FAR_PLANE = 100.0
config.FOV = math.pi / 3  -- 60 degrees

return config
