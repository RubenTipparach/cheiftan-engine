-- Fog Scene - Demonstrates depth fog with dithered blending
-- Cubes arranged in depth to show fog gradient

local config = require("config")
local mat4 = require("mat4")
local camera = require("camera")
local mesh = require("mesh")
local renderer_dda = require("renderer_dda")
local profiler = require("profiler")
local GIF = require("gif")

-- Rendering constants
local RENDER_WIDTH = config.RENDER_WIDTH
local RENDER_HEIGHT = config.RENDER_HEIGHT
local NUM_CUBES = 200
local renderCanvas
local renderImage

local cam
local time = 0

-- Scene objects
local cubes = {}
local cube = nil
local texture
local textureData
local gifRecorder = nil
local isRecording = false

function love.load()
    love.window.setTitle("Fog Scene - Depth Fog with Dithering")

    -- Initialize DDA renderer
    renderer_dda.init(RENDER_WIDTH, RENDER_HEIGHT)
    print("DDA Renderer initialized for fog scene")

    -- Enable fog (near, far, r, g, b)
    renderer_dda.setFog(true, 5, 50, 32, 32, 48)  -- Dark blue fog

    -- Create canvas for scaling
    renderCanvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT)
    renderCanvas:setFilter("nearest", "nearest")

    -- Load texture
    textureData = love.image.newImageData("assets/checkered_placeholder.png")
    texture = love.graphics.newImage(textureData)
    texture:setFilter("nearest", "nearest")

    -- Initialize camera
    cam = camera.new(0, 5, -10)
    camera.updateVectors(cam)

    -- Create cube mesh
    cube = mesh.createCube()

    -- Generate cubes arranged in depth
    math.randomseed(os.time())
    for i = 1, NUM_CUBES do
        -- Arrange cubes in a grid extending into the distance
        local gridX = (i % 10) - 5
        local gridZ = math.floor(i / 10)

        table.insert(cubes, {
            x = gridX * 4 + math.random(-1, 1),
            y = math.random(-3, 3),
            z = gridZ * 5 + math.random(-2, 2),
            rotX = math.random() * math.pi * 2,
            rotY = math.random() * math.pi * 2,
            rotZ = math.random() * math.pi * 2,
            rotSpeedX = (math.random() - 0.5) * 0.5,
            rotSpeedY = (math.random() - 0.5) * 0.5,
            rotSpeedZ = (math.random() - 0.5) * 0.5
        })
    end
    print("Generated " .. #cubes .. " cubes with fog")

    -- Create reusable render image
    renderImage = love.graphics.newImage(renderer_dda.getImageData())
    renderImage:setFilter("nearest", "nearest")
end

function love.update(dt)
    time = time + dt

    -- Update cube rotations
    for _, c in ipairs(cubes) do
        c.rotX = c.rotX + c.rotSpeedX * dt
        c.rotY = c.rotY + c.rotSpeedY * dt
        c.rotZ = c.rotZ + c.rotSpeedZ * dt
    end

    -- Update camera
    camera.update(cam, dt, 15.0, 2.0)
end

function love.draw()
    profiler.startFrame()

    -- Clear buffers
    renderer_dda.clearBuffers()

    profiler.start("matrices")
    -- Create view and projection matrices
    local viewMatrix = camera.getViewMatrix(cam)
    local projectionMatrix = mat4.perspective(70, RENDER_WIDTH/RENDER_HEIGHT, 0.1, 100)
    local vpMatrix = mat4.multiply(projectionMatrix, viewMatrix)
    profiler.stop("matrices")

    profiler.start("render_cubes")
    local trianglesDrawn = 0

    -- Draw cubes
    for _, cubeInstance in ipairs(cubes) do
        -- Build model matrix
        local modelMatrix = mat4.translation(cubeInstance.x, cubeInstance.y, cubeInstance.z)
        modelMatrix = mat4.multiply(modelMatrix, mat4.rotationY(cubeInstance.rotY))
        modelMatrix = mat4.multiply(modelMatrix, mat4.rotationX(cubeInstance.rotX))
        modelMatrix = mat4.multiply(modelMatrix, mat4.rotationZ(cubeInstance.rotZ))

        local mvpMatrix = mat4.multiply(vpMatrix, modelMatrix)

        -- Set matrices
        renderer_dda.setMatrices(mvpMatrix, cam.pos)

        -- Draw all triangles
        for _, tri in ipairs(cube.triangles) do
            local v1 = cube.vertices[tri[1]]
            local v2 = cube.vertices[tri[2]]
            local v3 = cube.vertices[tri[3]]

            renderer_dda.drawTriangle3D(v1, v2, v3, texture, textureData)
            trianglesDrawn = trianglesDrawn + 1
        end
    end
    profiler.stop("render_cubes")

    -- Update existing image
    profiler.start("convert_draw")
    renderImage:replacePixels(renderer_dda.getImageData())

    local windowWidth, windowHeight = love.graphics.getDimensions()
    local renderStats = renderer_dda.getStats()

    -- Draw to canvas (no UI - just the foggy scene)
    love.graphics.setCanvas(renderCanvas)
    love.graphics.clear(0, 0, 0)
    love.graphics.draw(renderImage, 0, 0)
    love.graphics.setCanvas()

    -- Draw canvas to screen
    local scaleX = windowWidth / RENDER_WIDTH
    local scaleY = windowHeight / RENDER_HEIGHT
    local scale = math.min(scaleX, scaleY)
    local offsetX = (windowWidth - RENDER_WIDTH * scale) / 2
    local offsetY = (windowHeight - RENDER_HEIGHT * scale) / 2

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(renderCanvas, offsetX, offsetY, 0, scale, scale)
    profiler.stop("convert_draw")

    profiler.endFrame()

    -- Capture frame for GIF
    if isRecording and gifRecorder then
        local frameCapture = renderCanvas:newImageData()
        gifRecorder:addFrame(frameCapture)
    end
end

function love.keypressed(key)
    if key == "escape" then
        local scene_manager = require("scene_manager")
        scene_manager.switch("menu")
    elseif key == "f8" then
        if not isRecording then
            gifRecorder = GIF.new(RENDER_WIDTH, RENDER_HEIGHT, 3)
            isRecording = true
            print("Started GIF recording")
        else
            isRecording = false
            local filename = "fog_" .. os.time() .. ".gif"
            gifRecorder:save(filename)
            print("Saved GIF: " .. filename .. " (" .. #gifRecorder.frames .. " frames)")
            gifRecorder = nil
        end
    elseif key == "f9" then
        local saveDir = love.filesystem.getSaveDirectory()
        print("Opening save directory: " .. saveDir)
        os.execute('start "" "' .. saveDir .. '"')
    end
end

return {
    load = love.load,
    update = love.update,
    draw = love.draw,
    keypressed = love.keypressed
}
