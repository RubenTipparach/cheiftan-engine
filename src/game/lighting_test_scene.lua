-- Lighting Test Scene
-- Demonstrates per-vertex lighting with interactive light control
-- Ported from Picotron lounge lighting test

local config = require("config")
local mat4 = require("mat4")
local camera = require("camera")
local mesh = require("mesh")
local renderer_dda = require("renderer_dda")
local lighting = require("lighting")
local vec3 = require("vec3")

-- Rendering constants
local RENDER_WIDTH = config.RENDER_WIDTH
local RENDER_HEIGHT = config.RENDER_HEIGHT

local cam
local renderCanvas, renderImage
local viewMatrix, projectionMatrix

-- Light state
local lightPos = {x = 0, y = .5, z = 0}
local lightRadius = 15.0
local lightBrightness = 1.0
local draggingLight = false
local lastDragMouseX, lastDragMouseY = 0, 0
local lightDragSpeed = 0.01

-- Test objects
local testCube
local testPyramid
local testSphere
local testShip
local gridFloor
local texture1, texture1Data
local texture2, texture2Data
local shipTexture, shipTextureData

-- Generate a low poly sphere (icosphere-style)
local function generateSphere(subdivisions)
    local verts = {}
    local triangles = {}

    -- Simple UV sphere with latitude/longitude
    local rings = subdivisions or 6
    local sectors = subdivisions * 2 or 12

    -- Top vertex
    table.insert(verts, {pos = {0, 0.5, 0}, uv = {4, 0}})

    -- Middle rings
    for ring = 1, rings - 1 do
        local theta = (ring / rings) * math.pi
        local y = 0.5 * math.cos(theta)
        local ringRadius = 0.5 * math.sin(theta)

        for sector = 0, sectors - 1 do
            local phi = (sector / sectors) * 2 * math.pi
            local x = ringRadius * math.cos(phi)
            local z = ringRadius * math.sin(phi)

            local u = (sector / sectors) * 8
            local v = (ring / rings) * 8

            table.insert(verts, {pos = {x, y, z}, uv = {u, v}})
        end
    end

    -- Bottom vertex
    table.insert(verts, {pos = {0, -0.5, 0}, uv = {4, 8}})

    -- Top cap triangles (reversed winding)
    for sector = 0, sectors - 1 do
        local next = (sector + 1) % sectors
        table.insert(triangles, {1, 2 + sector, 2 + next})
    end

    -- Middle quads (as triangles) (reversed winding)
    for ring = 0, rings - 3 do
        local ringStart = 2 + ring * sectors
        local nextRingStart = ringStart + sectors

        for sector = 0, sectors - 1 do
            local next = (sector + 1) % sectors

            local a = ringStart + sector
            local b = ringStart + next
            local c = nextRingStart + next
            local d = nextRingStart + sector

            table.insert(triangles, {a, c, b})
            table.insert(triangles, {a, d, c})
        end
    end

    -- Bottom cap triangles (reversed winding)
    local bottomIdx = #verts
    local lastRingStart = 2 + (rings - 2) * sectors
    for sector = 0, sectors - 1 do
        local next = (sector + 1) % sectors
        table.insert(triangles, {lastRingStart + sector, bottomIdx, lastRingStart + next})
    end

    return {vertices = verts, triangles = triangles}
end

-- Generate a grid floor
local function generateGridFloor(size, cellSize)
    local verts = {}
    local triangles = {}
    local halfSize = size / 2

    -- Generate grid vertices (scaled up UV)
    for z = 0, size do
        for x = 0, size do
            local wx = (x - halfSize) * cellSize
            local wz = (z - halfSize) * cellSize
            table.insert(verts, {pos = {wx, 0, wz}, uv = {x * 8, z * 8}})
        end
    end

    -- Generate grid faces (two triangles per cell)
    for z = 0, size - 1 do
        for x = 0, size - 1 do
            local tl = z * (size + 1) + x + 1
            local tr = tl + 1
            local bl = (z + 1) * (size + 1) + x + 1
            local br = bl + 1

            -- Triangle 1
            table.insert(triangles, {tl, tr, bl})
            -- Triangle 2
            table.insert(triangles, {tr, br, bl})
        end
    end

    return {vertices = verts, triangles = triangles}
end

-- Project world point to screen coordinates
local function projectToScreen(worldX, worldY, worldZ)
    local worldPos = {worldX, worldY, worldZ, 1}
    local viewPos = mat4.multiplyVec4(viewMatrix, worldPos)
    local clipPos = mat4.multiplyVec4(projectionMatrix, viewPos)

    if clipPos[4] > 0.01 then
        local ndcX = clipPos[1] / clipPos[4]
        local ndcY = clipPos[2] / clipPos[4]

        local screenX = (ndcX + 1) * 0.5 * RENDER_WIDTH
        local screenY = (1 - ndcY) * 0.5 * RENDER_HEIGHT

        return screenX, screenY, clipPos[4] > 0
    end

    return 0, 0, false
end

-- Draw wireframe circle for light widget
local function drawLightWidget()
    local segments = 16
    local points = {}

    -- Horizontal circle (XZ plane)
    for i = 0, segments do
        local angle = (i / segments) * 2 * math.pi
        local x = lightPos.x + math.cos(angle) * 0.3
        local z = lightPos.z + math.sin(angle) * 0.3
        local sx, sy, visible = projectToScreen(x, lightPos.y, z)
        if visible then
            table.insert(points, {x = sx, y = sy})
        end
    end

    -- Draw horizontal circle
    love.graphics.setColor(1, 1, 0)  -- Yellow
    for i = 1, #points - 1 do
        love.graphics.line(points[i].x, points[i].y, points[i+1].x, points[i+1].y)
    end

    -- Vertical circle (XY plane)
    points = {}
    for i = 0, segments do
        local angle = (i / segments) * 2 * math.pi
        local x = lightPos.x + math.cos(angle) * 0.3
        local y = lightPos.y + math.sin(angle) * 0.3
        local sx, sy, visible = projectToScreen(x, y, lightPos.z)
        if visible then
            table.insert(points, {x = sx, y = sy})
        end
    end

    -- Draw vertical circle
    for i = 1, #points - 1 do
        love.graphics.line(points[i].x, points[i].y, points[i+1].x, points[i+1].y)
    end

    -- Draw light radius indicator (horizontal circle)
    points = {}
    for i = 0, segments * 2 do
        local angle = (i / (segments * 2)) * 2 * math.pi
        local x = lightPos.x + math.cos(angle) * lightRadius
        local z = lightPos.z + math.sin(angle) * lightRadius
        local sx, sy, visible = projectToScreen(x, lightPos.y, z)
        if visible then
            table.insert(points, {x = sx, y = sy})
        end
    end

    -- Draw radius circle
    love.graphics.setColor(1, 0.5, 0)  -- Orange
    for i = 1, #points - 1 do
        love.graphics.line(points[i].x, points[i].y, points[i+1].x, points[i+1].y)
    end
end

-- Draw a mesh with per-vertex lighting (wrapper for lighting.drawLitMesh)
local function drawLitMesh(meshData, modelMatrix, texture, texData)
    lighting.drawLitMesh(meshData, modelMatrix, texture, texData, renderer_dda, mat4, viewMatrix, projectionMatrix, cam.pos)
end

function love.load()
    love.window.setTitle("Lighting Test - DDA Renderer")

    -- Initialize renderer
    renderer_dda.init(RENDER_WIDTH, RENDER_HEIGHT)
    renderer_dda.setFog(false)

    -- Initialize lighting
    lighting.clearLights()
    lighting.addLight("main", lightPos.x, lightPos.y, lightPos.z, lightRadius, lightBrightness)
    lighting.setAmbient(0.05)

    -- Create canvas
    renderCanvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT)
    renderCanvas:setFilter("nearest", "nearest")

    -- Load textures
    texture1Data = love.image.newImageData("assets/checkered_placeholder.png")
    texture1 = love.graphics.newImage(texture1Data)
    texture1:setFilter("nearest", "nearest")

    texture2Data = love.image.newImageData("assets/checkered_placeholde2r.png")
    texture2 = love.graphics.newImage(texture2Data)
    texture2:setFilter("nearest", "nearest")

    shipTextureData = love.image.newImageData("assets/Ship_1_finish.png")
    shipTexture = love.graphics.newImage(shipTextureData)
    shipTexture:setFilter("nearest", "nearest")

    -- Initialize camera (facing forward after 180° rotation)
    cam = camera.new(0, 5, 5)
    cam.yaw = 0
    cam.pitch = -math.pi / 4  -- 45 degrees down
    camera.updateVectors(cam)

    -- Load OBJ models
    local obj_loader = require("obj_loader")
    testShip = obj_loader.load("assets/ship_1.obj")

    -- Generate test objects
    testCube = mesh.createCube()
    testPyramid = mesh.createPyramid()
    testSphere = generateSphere(6)
    gridFloor = generateGridFloor(10, 1)

    -- Create reusable render image
    renderImage = love.graphics.newImage(renderer_dda.getImageData())
    renderImage:setFilter("nearest", "nearest")

    print("Lighting test scene loaded - lighting is now functional!")
end

local time = 0

function love.update(dt)
    time = time + dt
    camera.update(cam, dt, 3.0, 1.5)

    -- Mouse-based light dragging in XZ plane (Picotron style)
    local mx, my = love.mouse.getPosition()
    if love.mouse.isDown(2) then  -- Right mouse button
        if not draggingLight then
            draggingLight = true
            lastDragMouseX = mx
            lastDragMouseY = my
        else
            -- Calculate mouse delta
            local dx = mx - lastDragMouseX
            local dy = my - lastDragMouseY

            -- Move light in XZ plane using camera-relative directions
            local forwardX = math.sin(cam.yaw)
            local forwardZ = math.cos(cam.yaw)
            local rightX = math.cos(cam.yaw)
            local rightZ = -math.sin(cam.yaw)

            -- Apply delta movement (inverted directions)
            lightPos.x = lightPos.x + rightX * dx * lightDragSpeed + forwardX * dy * lightDragSpeed
            lightPos.z = lightPos.z + rightZ * dx * lightDragSpeed + forwardZ * dy * lightDragSpeed

            lastDragMouseX = mx
            lastDragMouseY = my
        end
    else
        draggingLight = false
    end

    -- Keyboard light controls
    if love.keyboard.isDown("i") then lightPos.y = lightPos.y + dt * 2 end
    if love.keyboard.isDown("k") then lightPos.y = lightPos.y - dt * 2 end
    if love.keyboard.isDown("j") then lightPos.x = lightPos.x - dt * 2 end
    if love.keyboard.isDown("l") then lightPos.x = lightPos.x + dt * 2 end
    if love.keyboard.isDown("u") then lightPos.z = lightPos.z - dt * 2 end
    if love.keyboard.isDown("o") then lightPos.z = lightPos.z + dt * 2 end

    -- Adjust light radius
    if love.keyboard.isDown("=") or love.keyboard.isDown("+") then
        lightRadius = lightRadius + dt * 2
    end
    if love.keyboard.isDown("-") or love.keyboard.isDown("_") then
        lightRadius = math.max(0.5, lightRadius - dt * 2)
    end

    -- Adjust light brightness
    if love.keyboard.isDown("[") then
        lightBrightness = math.max(0.1, lightBrightness - dt)
    end
    if love.keyboard.isDown("]") then
        lightBrightness = math.min(3.0, lightBrightness + dt)
    end

    -- Update light in lighting system
    lighting.addLight("main", lightPos.x, lightPos.y, lightPos.z, lightRadius, lightBrightness)
end

function love.draw()
    -- Clear buffers
    renderer_dda.clearBuffers()

    -- Set up matrices
    viewMatrix = camera.getViewMatrix(cam)
    projectionMatrix = mat4.perspective(
        math.pi / 3,  -- 60 degree FOV
        RENDER_WIDTH / RENDER_HEIGHT,
        0.1,
        100.0
    )

    -- Draw grid floor with lighting
    local floorMatrix = mat4.identity()
    drawLitMesh(gridFloor, floorMatrix, texture1, texture1Data)

    -- Draw cube at (-3, 0.25, 0) with texture1 (scaled down 50%)
    local cubeMatrix = mat4.identity()
    cubeMatrix = mat4.multiply(cubeMatrix, mat4.translation(-3, 0.25, 0))
    cubeMatrix = mat4.multiply(cubeMatrix, mat4.scale(0.5, 0.5, 0.5))
    drawLitMesh(testCube, cubeMatrix, texture1, texture1Data)

    -- Draw sphere at (3, 0.5, 0) with texture1
    local sphereMatrix = mat4.identity()
    sphereMatrix = mat4.multiply(sphereMatrix, mat4.translation(3, 0.5, 0))
    drawLitMesh(testSphere, sphereMatrix, texture1, texture1Data)

    -- Draw ship at (0, 1, -3) with ship texture
    local shipMatrix = mat4.identity()
    shipMatrix = mat4.multiply(shipMatrix, mat4.translation(0, 1, -3))
    shipMatrix = mat4.multiply(shipMatrix, mat4.scale(0.5, 0.5, 0.5))
    drawLitMesh(testShip, shipMatrix, shipTexture, shipTextureData)

    -- Draw scattered pyramids with mixed textures
    local pyramidPositions = {
        {-2, 0, -2, texture2, texture2Data},
        {1, 0, -1.5, texture1, texture1Data},
        {-1.5, 0, 2, texture2, texture2Data},
        {2.5, 0, 1, texture1, texture1Data},
        {0, 0, 0, texture2, texture2Data}
    }

    for _, p in ipairs(pyramidPositions) do
        local pyramidMatrix = mat4.identity()
        pyramidMatrix = mat4.multiply(pyramidMatrix, mat4.translation(p[1], p[2], p[3]))
        drawLitMesh(testPyramid, pyramidMatrix, p[4], p[5])
    end

    -- Update render image
    renderImage:replacePixels(renderer_dda.getImageData())

    local windowWidth, windowHeight = love.graphics.getDimensions()

    -- Draw to canvas
    love.graphics.setCanvas(renderCanvas)
    love.graphics.clear(0, 0, 0)
    love.graphics.draw(renderImage, 0, 0)

    -- Draw light widget on top of render
    drawLightWidget()

    -- Draw UI
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)
    love.graphics.print(string.format("Light: (%.1f, %.1f, %.1f)", lightPos.x, lightPos.y, lightPos.z), 10, 25)
    love.graphics.print(string.format("Radius: %.1f | Brightness: %.1f", lightRadius, lightBrightness), 10, 40)
    love.graphics.print("Right-click drag: Move light XZ | IJKL/UO: Move | +/-: Radius | [/]: Brightness", 10, 55)

    love.graphics.setCanvas()

    -- Draw canvas to screen
    local scaleX = windowWidth / RENDER_WIDTH
    local scaleY = windowHeight / RENDER_HEIGHT
    local scale = math.min(scaleX, scaleY)
    local offsetX = (windowWidth - RENDER_WIDTH * scale) / 2
    local offsetY = (windowHeight - RENDER_HEIGHT * scale) / 2

    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(renderCanvas, offsetX, offsetY, 0, scale, scale)
end

function love.keypressed(key)
    if key == "escape" then
        local scene_manager = require("scene_manager")
        scene_manager.switch("menu")
    end
end

return {
    load = love.load,
    update = love.update,
    draw = love.draw,
    keypressed = love.keypressed
}
