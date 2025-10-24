-- City Scene for DDA Renderer Validation
-- Creates a city with cube buildings and a low-poly sphere

local mat4 = require("mat4")
local vec3 = require("vec3")
local mesh = require("mesh")
local renderer_dda = require("renderer_dda")
local profiler = require("profiler")

-- Rendering constants
local RENDER_WIDTH = 960
local RENDER_HEIGHT = 540
local renderCanvas

-- Camera
local camera = {
    pos = vec3.new(0, 5, -20),
    rotation = {x = 0, y = 0, z = 0}
}

local time = 0

-- Scene objects
local buildings = {}
local sphere = nil
local ground = nil

-- Textures
local texture1
local texture2
local textureData1
local textureData2

function love.load()
    love.window.setTitle("City Scene - DDA Renderer Validation")

    -- Initialize renderer
    renderer_dda.init(RENDER_WIDTH, RENDER_HEIGHT)
    print("DDA Renderer initialized")

    -- Create canvas for scaling
    renderCanvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT)
    renderCanvas:setFilter("nearest", "nearest")

    -- Load textures
    textureData1 = love.image.newImageData("checkered_placeholder.png")
    texture1 = love.graphics.newImage(textureData1)
    texture1:setFilter("nearest", "nearest")

    textureData2 = love.image.newImageData("checkered_placeholde2r.png")
    texture2 = love.graphics.newImage(textureData2)
    texture2:setFilter("nearest", "nearest")

    print("Textures loaded")

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

    -- Create a low-poly sphere (sun/moon)
    sphere = {
        mesh = mesh.createSphere(8, 6),
        x = 10,
        y = 15,
        z = 20,
        scale = 2,
        texture = texture2,
        textureData = textureData2
    }

    -- Create ground plane (2 large triangles)
    ground = {
        triangles = {
            {1, 2, 3},
            {1, 3, 4}
        },
        vertices = {
            {pos = {-50, 0, -10}, uv = {0, 0}},
            {pos = {50, 0, -10}, uv = {25, 0}},
            {pos = {50, 0, 50}, uv = {25, 30}},
            {pos = {-50, 0, 50}, uv = {0, 30}}
        },
        texture = texture1
    }

    print("City scene created with " .. #buildings .. " buildings")
end

function love.update(dt)
    time = time + dt

    -- Camera rotation with arrow keys
    if love.keyboard.isDown("left") then
        camera.rotation.y = camera.rotation.y - dt * 2
    end
    if love.keyboard.isDown("right") then
        camera.rotation.y = camera.rotation.y + dt * 2
    end
    if love.keyboard.isDown("up") then
        camera.rotation.x = camera.rotation.x - dt * 2
    end
    if love.keyboard.isDown("down") then
        camera.rotation.x = camera.rotation.x + dt * 2
    end

    -- Camera movement
    local moveSpeed = 10
    local yaw = camera.rotation.y
    local forwardX = math.sin(yaw)
    local forwardZ = math.cos(yaw)
    local rightX = math.cos(yaw)
    local rightZ = -math.sin(yaw)

    if love.keyboard.isDown("w") then
        camera.pos.x = camera.pos.x + forwardX * moveSpeed * dt
        camera.pos.z = camera.pos.z + forwardZ * moveSpeed * dt
    end
    if love.keyboard.isDown("s") then
        camera.pos.x = camera.pos.x - forwardX * moveSpeed * dt
        camera.pos.z = camera.pos.z - forwardZ * moveSpeed * dt
    end
    if love.keyboard.isDown("a") then
        camera.pos.x = camera.pos.x - rightX * moveSpeed * dt
        camera.pos.z = camera.pos.z - rightZ * moveSpeed * dt
    end
    if love.keyboard.isDown("d") then
        camera.pos.x = camera.pos.x + rightX * moveSpeed * dt
        camera.pos.z = camera.pos.z + rightZ * moveSpeed * dt
    end
    if love.keyboard.isDown("space") then
        camera.pos.y = camera.pos.y + moveSpeed * dt
    end
    if love.keyboard.isDown("lshift") then
        camera.pos.y = camera.pos.y - moveSpeed * dt
    end

    -- Rotate sphere
    if sphere then
        sphere.x = 10 * math.cos(time * 0.3)
        sphere.z = 20 + 5 * math.sin(time * 0.3)
    end
end

function love.draw()
    profiler.startFrame()

    -- Clear buffers
    renderer_dda.clearBuffers()

    profiler.start("matrices")
    -- Create view and projection matrices
    local viewMatrix = mat4.identity()
    viewMatrix = mat4.multiply(viewMatrix, mat4.rotationX(camera.rotation.x))
    viewMatrix = mat4.multiply(viewMatrix, mat4.rotationY(camera.rotation.y))
    viewMatrix = mat4.multiply(viewMatrix, mat4.translation(camera.pos.x, camera.pos.y, camera.pos.z))

    local projectionMatrix = mat4.perspective(70, RENDER_WIDTH/RENDER_HEIGHT, 0.1, 100)
    local vpMatrix = mat4.multiply(projectionMatrix, viewMatrix)
    profiler.stop("matrices")

    profiler.start("render_scene")
    local trianglesDrawn = 0

    -- Helper function to transform and draw mesh
    local function drawMesh(meshData, modelMatrix, texture, texData)
        local mvpMatrix = mat4.multiply(vpMatrix, modelMatrix)

        for _, tri in ipairs(meshData.triangles) do
            local v1 = meshData.vertices[tri[1]]
            local v2 = meshData.vertices[tri[2]]
            local v3 = meshData.vertices[tri[3]]

            -- Transform vertices
            local p1 = mat4.multiplyVec4(mvpMatrix, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
            local p2 = mat4.multiplyVec4(mvpMatrix, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
            local p3 = mat4.multiplyVec4(mvpMatrix, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

            -- Skip if all behind camera
            if p1[4] <= 0 and p2[4] <= 0 and p3[4] <= 0 then
                goto continue
            end

            -- Project to screen space
            local s1x = (p1[1] / p1[4] + 1) * RENDER_WIDTH * 0.5
            local s1y = (1 - p1[2] / p1[4]) * RENDER_HEIGHT * 0.5
            local s2x = (p2[1] / p2[4] + 1) * RENDER_WIDTH * 0.5
            local s2y = (1 - p2[2] / p2[4]) * RENDER_HEIGHT * 0.5
            local s3x = (p3[1] / p3[4] + 1) * RENDER_WIDTH * 0.5
            local s3y = (1 - p3[2] / p3[4]) * RENDER_HEIGHT * 0.5

            -- Backface culling
            local edge1x = s2x - s1x
            local edge1y = s2y - s1y
            local edge2x = s3x - s1x
            local edge2y = s3y - s1y
            local cross = edge1x * edge2y - edge1y * edge2x

            if cross >= 0 then
                goto continue
            end

            -- Prepare vertex data for DDA renderer
            -- Format: {x, y, w, u_over_w, v_over_w, z}
            local w1 = 1 / p1[4]
            local w2 = 1 / p2[4]
            local w3 = 1 / p3[4]

            local vA = {
                s1x, s1y,
                w1,
                v1.uv[1] * w1, v1.uv[2] * w1,
                p1[3] / p1[4]
            }
            local vB = {
                s2x, s2y,
                w2,
                v2.uv[1] * w2, v2.uv[2] * w2,
                p2[3] / p2[4]
            }
            local vC = {
                s3x, s3y,
                w3,
                v3.uv[1] * w3, v3.uv[2] * w3,
                p3[3] / p3[4]
            }

            renderer_dda.drawTriangle(vA, vB, vC, texture, texData)
            trianglesDrawn = trianglesDrawn + 1

            ::continue::
        end
    end

    -- Draw ground
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

    -- Draw sphere
    if sphere and sphere.mesh then
        profiler.start("  sphere")
        local sphereModel = mat4.translation(sphere.x, sphere.y, sphere.z)
        sphereModel = mat4.multiply(sphereModel, mat4.scale(sphere.scale, sphere.scale, sphere.scale))
        sphereModel = mat4.multiply(sphereModel, mat4.rotationY(time))
        drawMesh(sphere.mesh, sphereModel, sphere.texture, sphere.textureData)
        profiler.stop("  sphere")
    end

    profiler.stop("render_scene")

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
    love.graphics.print("DDA SCANLINE RENDERER", 10, 10)
    love.graphics.print("Triangles: " .. trianglesDrawn, 10, 30)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 50)
    love.graphics.print("Camera: (" .. math.floor(camera.pos.x) .. ", " .. math.floor(camera.pos.y) .. ", " .. math.floor(camera.pos.z) .. ")", 10, 70)

    -- Profiler
    local y = 90
    y = profiler.draw("matrices", 10, y)
    y = profiler.draw("render_scene", 10, y)
    y = profiler.draw("  ground", 10, y, {0.4, 0.6, 1.0})
    y = profiler.draw("  buildings", 10, y, {0.4, 0.6, 1.0})
    y = profiler.draw("  sphere", 10, y, {0.4, 0.6, 1.0})
    y = profiler.draw("convert_draw", 10, y)
    y = y + 5
    profiler.draw("total", 10, y)

    -- Controls
    love.graphics.print("WASD: Move | Arrows: Rotate | Space/Shift: Up/Down", 10, windowHeight - 40)
    love.graphics.print("ESC: Quit", 10, windowHeight - 20)

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
