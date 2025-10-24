-- City Scene for DDA Renderer Validation
-- Creates a city with cube buildings and a low-poly sphere

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
local renderCanvas
local renderImage

local cam

local time = 0

-- Scene objects
local buildings = {}
local groundSpheres = {}
local ground = nil

-- Textures
local texture1
local texture2
local textureData1
local textureData2

-- GIF recording
local gifRecorder = nil
local isRecording = false

function love.load()
    love.window.setTitle("City Scene - DDA Renderer Validation")

    -- Initialize renderer
    renderer_dda.init(RENDER_WIDTH, RENDER_HEIGHT)
    print("DDA Renderer initialized")

    -- Create canvas for scaling
    renderCanvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT)
    renderCanvas:setFilter("nearest", "nearest")

    -- Load textures
    textureData1 = love.image.newImageData("assets/checkered_placeholder.png")
    texture1 = love.graphics.newImage(textureData1)
    texture1:setFilter("nearest", "nearest")

    textureData2 = love.image.newImageData("assets/checkered_placeholde2r.png")
    texture2 = love.graphics.newImage(textureData2)
    texture2:setFilter("nearest", "nearest")

    print("Textures loaded")

    -- Initialize camera
    cam = camera.new(0, 5, -20)
    camera.updateVectors(cam)

    -- Create reusable render image
    renderImage = love.graphics.newImage(renderer_dda.getImageData())
    renderImage:setFilter("nearest", "nearest")

    -- Create buildings (cubes at various positions)
    local cube = mesh.createCube()

    -- Grid of buildings
    for x = -3, 3, 2 do
        for z = 5, 25, 5 do
            local height = math.random(3, 8)
            table.insert(buildings, {
                mesh = cube,
                x = x * 3,
                y = height / 2,
                z = z,
                scaleX = 1.5,
                scaleY = height,
                scaleZ = 1.5,
                texture = (x + z) % 2 == 0 and texture1 or texture2,
                textureData = (x + z) % 2 == 0 and textureData1 or textureData2
            })
        end
    end

    -- Add a few taller buildings
    table.insert(buildings, {
        mesh = cube,
        x = 0,
        y = 6,
        z = 15,
        scaleX = 2,
        scaleY = 12,
        scaleZ = 2,
        texture = texture1,
        textureData = textureData1
    })

    table.insert(buildings, {
        mesh = cube,
        x = -8,
        y = 5,
        z = 20,
        scaleX = 2,
        scaleY = 10,
        scaleZ = 2,
        texture = texture2,
        textureData = textureData2
    })

    table.insert(buildings, {
        mesh = cube,
        x = 8,
        y = 4,
        z = 12,
        scaleX = 1.5,
        scaleY = 8,
        scaleZ = 1.5,
        texture = texture1,
        textureData = textureData1
    })

    -- Create ground spheres (half-buried, stationary)
    -- Use lower poly count for performance (6x6 = 72 tris each)
    local sphereMesh = mesh.createSphere(6, 6)

    -- Place spheres at various positions, half-buried in ground
    table.insert(groundSpheres, {
        mesh = sphereMesh,
        x = -10,
        y = -1.5,  -- Half-buried
        z = 15,
        scale = 3,
        texture = texture1,
        textureData = textureData1,
        rotSpeed = 0.1
    })

    table.insert(groundSpheres, {
        mesh = sphereMesh,
        x = 12,
        y = -2,
        z = 25,
        scale = 4,
        texture = texture2,
        textureData = textureData2,
        rotSpeed = -0.08
    })

    table.insert(groundSpheres, {
        mesh = sphereMesh,
        x = 0,
        y = -1,
        z = 8,
        scale = 2,
        texture = texture1,
        textureData = textureData1,
        rotSpeed = 0.12
    })

    table.insert(groundSpheres, {
        mesh = sphereMesh,
        x = -15,
        y = -2.5,
        z = 30,
        scale = 5,
        texture = texture2,
        textureData = textureData2,
        rotSpeed = 0.05
    })

    -- Create subdivided ground plane (10x10 grid for better culling)
    ground = {
        triangles = {},
        vertices = {}
    }

    local gridSize = 10
    local groundWidth = 100  -- -50 to 50
    local groundDepth = 60   -- -10 to 50
    local startX = -50
    local startZ = -10
    local stepX = groundWidth / gridSize
    local stepZ = groundDepth / gridSize

    -- Generate vertices
    for z = 0, gridSize do
        for x = 0, gridSize do
            local worldX = startX + x * stepX
            local worldZ = startZ + z * stepZ
            local u = (x / gridSize) * 25
            local v = (z / gridSize) * 30
            table.insert(ground.vertices, {pos = {worldX, 0, worldZ}, uv = {u, v}})
        end
    end

    -- Generate triangles (CCW winding for upward-facing normals)
    for z = 0, gridSize - 1 do
        for x = 0, gridSize - 1 do
            local topLeft = z * (gridSize + 1) + x + 1
            local topRight = topLeft + 1
            local bottomLeft = (z + 1) * (gridSize + 1) + x + 1
            local bottomRight = bottomLeft + 1

            -- Two triangles per grid square (reversed winding for CCW)
            table.insert(ground.triangles, {topLeft, topRight, bottomLeft})
            table.insert(ground.triangles, {topRight, bottomRight, bottomLeft})
        end
    end

    print("City scene created with " .. #buildings .. " buildings")
end

function love.update(dt)
    time = time + dt

    -- Update camera
    camera.update(cam, dt, 10.0, 2.0)
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

    profiler.start("render_scene")
    local trianglesDrawn = 0

    -- Helper function to transform and draw mesh using new API
    local function drawMesh(meshData, modelMatrix, texture, texData, skipCulling)
        local mvpMatrix = mat4.multiply(vpMatrix, modelMatrix)

        -- Screen-space bounding box culling (skip for large objects like ground plane)
        if not skipCulling then
            -- Transform all vertices and compute AABB in clip space
            local minX, minY, minZ = math.huge, math.huge, math.huge
            local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
            local allBehindCamera = true

            for _, vertex in ipairs(meshData.vertices) do
                local pos = vertex.pos
                local clipPos = mat4.multiplyVec4(mvpMatrix, {pos[1], pos[2], pos[3], 1})
                local cx, cy, cz, cw = clipPos[1], clipPos[2], clipPos[3], clipPos[4]

                if cw > 0.01 then
                    allBehindCamera = false
                    -- Perspective divide to get NDC
                    local ndcX = cx / cw
                    local ndcY = cy / cw
                    local ndcZ = cz / cw

                    minX = math.min(minX, ndcX)
                    maxX = math.max(maxX, ndcX)
                    minY = math.min(minY, ndcY)
                    maxY = math.max(maxY, ndcY)
                    minZ = math.min(minZ, ndcZ)
                    maxZ = math.max(maxZ, ndcZ)
                end
            end

            -- Cull if entire mesh is behind camera or outside frustum
            if allBehindCamera or maxX < -1 or minX > 1 or maxY < -1 or minY > 1 or maxZ < -1 or minZ > 1 then
                return
            end
        end

        renderer_dda.setMatrices(mvpMatrix, cam.pos)

        for _, tri in ipairs(meshData.triangles) do
            local v1 = meshData.vertices[tri[1]]
            local v2 = meshData.vertices[tri[2]]
            local v3 = meshData.vertices[tri[3]]

            renderer_dda.drawTriangle3D(v1, v2, v3, texture, texData)
            trianglesDrawn = trianglesDrawn + 1
        end
    end

    -- Draw ground (now uses per-triangle culling)
    profiler.start("  ground")
    local groundModel = mat4.identity()
    drawMesh(ground, groundModel, texture1, textureData1)
    profiler.stop("  ground")

    -- Draw buildings
    profiler.start("  buildings")
    for _, building in ipairs(buildings) do
        local modelMatrix = mat4.translation(building.x, building.y, building.z)
        modelMatrix = mat4.multiply(modelMatrix, mat4.scale(building.scaleX, building.scaleY, building.scaleZ))
        drawMesh(building.mesh, modelMatrix, building.texture, building.textureData)
    end
    profiler.stop("  buildings")

    -- Draw ground spheres (stationary, slowly spinning)
    profiler.start("  spheres")
    for _, sph in ipairs(groundSpheres) do
        local sphereModel = mat4.translation(sph.x, sph.y, sph.z)
        sphereModel = mat4.multiply(sphereModel, mat4.scale(sph.scale, sph.scale, sph.scale))
        sphereModel = mat4.multiply(sphereModel, mat4.rotationY(time * sph.rotSpeed))
        drawMesh(sph.mesh, sphereModel, sph.texture, sph.textureData)
    end
    profiler.stop("  spheres")

    profiler.stop("render_scene")

    -- Update existing image (much faster than creating new one)
    profiler.start("convert_draw")
    renderImage:replacePixels(renderer_dda.getImageData())

    -- Get stats for UI
    local renderStats = renderer_dda.getStats()
    local windowWidth, windowHeight = love.graphics.getDimensions()

    -- Draw to canvas (including UI for GIF capture)
    love.graphics.setCanvas(renderCanvas)
    love.graphics.clear(0, 0, 0)
    love.graphics.draw(renderImage, 0, 0)

    -- Draw UI directly to canvas
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("DDA SCANLINE RENDERER - City Scene", 10, 10)
    love.graphics.print("Triangles: " .. trianglesDrawn .. " (Drawn: " .. renderStats.trianglesDrawn .. ", Culled: " .. renderStats.trianglesCulled .. ")", 10, 30)
    love.graphics.print("Pixels: " .. renderStats.pixelsDrawn, 10, 50)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 70)
    love.graphics.print("Camera: (" .. math.floor(cam.pos.x) .. ", " .. math.floor(cam.pos.y) .. ", " .. math.floor(cam.pos.z) .. ")", 10, 90)

    -- Profiler
    local y = 110
    y = profiler.draw("matrices", 10, y)
    y = profiler.draw("render_scene", 10, y)
    y = profiler.draw("  ground", 10, y, {0.4, 0.6, 1.0})
    y = profiler.draw("  buildings", 10, y, {0.4, 0.6, 1.0})
    y = profiler.draw("  spheres", 10, y, {0.4, 0.6, 1.0})
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
            local filename = "city_" .. os.time() .. ".gif"
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
