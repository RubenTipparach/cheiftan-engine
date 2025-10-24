-- 5000 Cubes Scene with DDA Renderer
-- Converted from main.lua to use new DDA scanline renderer

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
local NUM_CUBES = 1000
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
    love.window.setTitle("1000 Cubes - DDA Renderer")

    -- Initialize DDA renderer
    renderer_dda.init(RENDER_WIDTH, RENDER_HEIGHT)
    print("DDA Renderer initialized for cubes scene")

    -- Create canvas for scaling
    renderCanvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT)
    renderCanvas:setFilter("nearest", "nearest")

    -- Load texture
    textureData = love.image.newImageData("checkered_placeholder.png")
    texture = love.graphics.newImage(textureData)
    texture:setFilter("nearest", "nearest")
    print("Texture loaded: " .. texture:getWidth() .. "x" .. texture:getHeight())

    -- Initialize camera
    cam = camera.new(0, 0, -5)
    camera.updateVectors(cam)

    -- Create cube mesh
    cube = mesh.createCube()
    print("Cube loaded with " .. #cube.triangles .. " triangles")

    -- Generate cubes with random positions and rotations
    math.randomseed(os.time())
    for i = 1, NUM_CUBES do
        table.insert(cubes, {
            x = math.random(-50, 50),
            y = math.random(-50, 50),
            z = math.random(0, 100),
            rotX = math.random() * math.pi * 2,
            rotY = math.random() * math.pi * 2,
            rotZ = math.random() * math.pi * 2,
            rotSpeedX = (math.random() - 0.5) * 2,
            rotSpeedY = (math.random() - 0.5) * 2,
            rotSpeedZ = (math.random() - 0.5) * 2
        })
    end
    print("Generated " .. #cubes .. " cubes")

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
    camera.update(cam, dt, 30.0, 2.0)
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

    profiler.start("cube_sort")
    -- Sort cubes by depth (painter's algorithm)
    local sortedCubes = {}
    for i, cubeInstance in ipairs(cubes) do
        local dx = cubeInstance.x - cam.pos.x
        local dy = cubeInstance.y - cam.pos.y
        local dz = cubeInstance.z - cam.pos.z
        local depth = dx*dx + dy*dy + dz*dz
        table.insert(sortedCubes, {cube = cubeInstance, depth = depth})
    end
    table.sort(sortedCubes, function(a, b) return a.depth > b.depth end)
    profiler.stop("cube_sort")

    profiler.start("render_cubes")
    local trianglesDrawn = 0

    for _, sortedCube in ipairs(sortedCubes) do
        local cubeInstance = sortedCube.cube

        -- Build model matrix
        local modelMatrix = mat4.translation(cubeInstance.x, cubeInstance.y, cubeInstance.z)
        modelMatrix = mat4.multiply(modelMatrix, mat4.rotationY(cubeInstance.rotY))
        modelMatrix = mat4.multiply(modelMatrix, mat4.rotationX(cubeInstance.rotX))
        modelMatrix = mat4.multiply(modelMatrix, mat4.rotationZ(cubeInstance.rotZ))

        local mvpMatrix = mat4.multiply(vpMatrix, modelMatrix)

        -- Frustum cull entire cube
        local center = mat4.multiplyVec4(mvpMatrix, {0, 0, 0, 1})
        local cx, cy, cz, cw = center[1], center[2], center[3], center[4]
        local margin = 2.0
        local cubeVisible = cw > 0 and
                           cx >= -cw - margin and cx <= cw + margin and
                           cy >= -cw - margin and cy <= cw + margin and
                           cz >= -margin and cz <= cw + margin

        if cubeVisible then
            -- Set matrices for this cube
            renderer_dda.setMatrices(mvpMatrix, cam.pos)

            -- Draw all triangles with automatic clipping and backface culling
            for _, tri in ipairs(cube.triangles) do
                local v1 = cube.vertices[tri[1]]
                local v2 = cube.vertices[tri[2]]
                local v3 = cube.vertices[tri[3]]

                renderer_dda.drawTriangle3D(v1, v2, v3, texture, textureData)
                trianglesDrawn = trianglesDrawn + 1
            end
        end
    end
    profiler.stop("render_cubes")

    -- Update existing image (much faster than creating new one)
    profiler.start("convert_draw")
    renderImage:replacePixels(renderer_dda.getImageData())

    local windowWidth, windowHeight = love.graphics.getDimensions()
    local renderStats = renderer_dda.getStats()

    -- Draw to canvas (including UI for GIF capture)
    love.graphics.setCanvas(renderCanvas)
    love.graphics.clear(0, 0, 0)
    love.graphics.draw(renderImage, 0, 0)

    -- Draw UI directly to canvas
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("DDA RENDERER - 1000 Cubes", 10, 10)
    love.graphics.print("Cubes: " .. #cubes, 10, 30)
    love.graphics.print("Triangles: " .. trianglesDrawn .. " (Drawn: " .. renderStats.trianglesDrawn .. ", Culled: " .. renderStats.trianglesCulled .. ")", 10, 50)
    love.graphics.print("Pixels: " .. renderStats.pixelsDrawn, 10, 70)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 90)

    -- Profiler
    local blue = {0.4, 0.6, 1.0}
    local y = 110
    y = profiler.draw("matrices", 10, y)
    y = profiler.draw("cube_sort", 10, y)
    y = profiler.draw("render_cubes", 10, y)
    y = profiler.draw("convert_draw", 10, y)
    y = y + 5
    profiler.draw("total", 10, y)

    if isRecording then
        love.graphics.print("[RECORDING] Frames: " .. #gifRecorder.frames, 10, RENDER_HEIGHT - 20)
    end

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

    -- Capture frame for GIF AFTER all drawing is done
    if isRecording and gifRecorder then
        -- Capture the canvas with UI included
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
            -- Start recording
            gifRecorder = GIF.new(RENDER_WIDTH, RENDER_HEIGHT, 3)
            isRecording = true
            print("Started GIF recording")
        else
            -- Stop recording and save
            isRecording = false
            local filename = "1000cubes_" .. os.time() .. ".gif"
            gifRecorder:save(filename)
            print("Saved GIF: " .. filename .. " (" .. #gifRecorder.frames .. " frames)")
            gifRecorder = nil
        end
    elseif key == "f9" then
        -- Open the save directory where GIFs are stored
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
