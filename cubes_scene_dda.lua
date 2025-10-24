-- 5000 Cubes Scene with DDA Renderer
-- Converted from main.lua to use new DDA scanline renderer

local mat4 = require("mat4")
local camera = require("camera")
local mesh = require("mesh")
local renderer_dda = require("renderer_dda")
local profiler = require("profiler")

-- Rendering constants
local RENDER_WIDTH = 960
local RENDER_HEIGHT = 540
local NUM_CUBES = 5000
local renderCanvas

local cam

local time = 0

-- Scene objects
local cubes = {}
local cube = nil
local texture
local textureData

function love.load()
    love.window.setTitle("5000 Cubes - DDA Renderer")

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
            -- Process each triangle
            for _, tri in ipairs(cube.triangles) do
                local v1 = cube.vertices[tri[1]]
                local v2 = cube.vertices[tri[2]]
                local v3 = cube.vertices[tri[3]]

                -- Transform vertices
                local p1 = mat4.multiplyVec4(mvpMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
                local p2 = mat4.multiplyVec4(mvpMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
                local p3 = mat4.multiplyVec4(mvpMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

                -- Skip if all behind camera
                if p1[4] > 0 or p2[4] > 0 or p3[4] > 0 then
                    -- Project to screen space
                    local s1x = (p1[1] / p1[4] + 1) * RENDER_WIDTH * 0.5
                    local s1y = (1 - p1[2] / p1[4]) * RENDER_HEIGHT * 0.5
                    local s2x = (p2[1] / p2[4] + 1) * RENDER_WIDTH * 0.5
                    local s2y = (1 - p2[2] / p2[4]) * RENDER_HEIGHT * 0.5
                    local s3x = (p3[1] / p3[4] + 1) * RENDER_WIDTH * 0.5
                    local s3y = (1 - p3[2] / p3[4]) * RENDER_HEIGHT * 0.5

                    -- Prepare vertex data for DDA renderer
                    local w1 = 1 / p1[4]
                    local w2 = 1 / p2[4]
                    local w3 = 1 / p3[4]

                    -- Get texture dimensions
                    local texW = textureData:getWidth()
                    local texH = textureData:getHeight()

                    local vA = {
                        s1x, s1y,
                        w1,
                        v1.uv[1] * texW * w1, v1.uv[2] * texH * w1,
                        p1[3] / p1[4]
                    }
                    local vB = {
                        s2x, s2y,
                        w2,
                        v2.uv[1] * texW * w2, v2.uv[2] * texH * w2,
                        p2[3] / p2[4]
                    }
                    local vC = {
                        s3x, s3y,
                        w3,
                        v3.uv[1] * texW * w3, v3.uv[2] * texH * w3,
                        p3[3] / p3[4]
                    }

                    renderer_dda.drawTriangle(vA, vB, vC, texture, textureData)
                    trianglesDrawn = trianglesDrawn + 1
                end
            end
        end
    end
    profiler.stop("render_cubes")

    -- Convert ImageData to texture and draw
    profiler.start("convert_draw")
    local img = love.graphics.newImage(renderer_dda.getImageData())
    img:setFilter("nearest", "nearest")

    -- Draw to canvas
    love.graphics.setCanvas(renderCanvas)
    love.graphics.clear(0, 0, 0)
    love.graphics.draw(img, 0, 0)
    love.graphics.setCanvas()

    -- Draw canvas to screen
    local windowWidth, windowHeight = love.graphics.getDimensions()
    local scaleX = windowWidth / RENDER_WIDTH
    local scaleY = windowHeight / RENDER_HEIGHT
    local scale = math.min(scaleX, scaleY)
    local offsetX = (windowWidth - RENDER_WIDTH * scale) / 2
    local offsetY = (windowHeight - RENDER_HEIGHT * scale) / 2

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(renderCanvas, offsetX, offsetY, 0, scale, scale)
    profiler.stop("convert_draw")

    -- Draw UI
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("DDA RENDERER - 5000 Cubes", 10, 10)
    love.graphics.print("Cubes: " .. #cubes, 10, 30)
    love.graphics.print("Triangles: " .. trianglesDrawn, 10, 50)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 70)

    -- Profiler
    local blue = {0.4, 0.6, 1.0}
    local y = 90
    y = profiler.draw("matrices", 10, y)
    y = profiler.draw("cube_sort", 10, y)
    y = profiler.draw("render_cubes", 10, y)
    y = profiler.draw("convert_draw", 10, y)
    y = y + 5
    profiler.draw("total", 10, y)

    -- Controls
    love.graphics.print("WASD: Move | Arrows: Rotate | ESC: Menu", 10, windowHeight - 20)

    profiler.endFrame()
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
end

return {
    load = love.load,
    update = love.update,
    draw = love.draw,
    keypressed = love.keypressed
}
