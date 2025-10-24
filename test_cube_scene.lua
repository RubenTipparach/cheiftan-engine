-- Simple Test Scene - Single Spinning Cube with DDA Renderer
local mat4 = require("mat4")
local camera = require("camera")
local renderer_dda = require("renderer_dda")
local obj_loader = require("obj_loader")

-- Rendering constants
local RENDER_WIDTH = 960
local RENDER_HEIGHT = 540

local cam
local shipTexture, shipTextureData
local cubeTexture1, cubeTextureData1
local cubeTexture2, cubeTextureData2
local time = 0
local renderCanvas
local renderImage
local shipModel

function love.load()
    love.window.setTitle("Test Cube - DDA Renderer")

    -- Initialize DDA renderer
    renderer_dda.init(RENDER_WIDTH, RENDER_HEIGHT)
    print("DDA Renderer initialized: " .. RENDER_WIDTH .. "x" .. RENDER_HEIGHT)

    -- Create canvas
    renderCanvas = love.graphics.newCanvas(RENDER_WIDTH, RENDER_HEIGHT)
    renderCanvas:setFilter("nearest", "nearest")

    -- Load ship texture
    shipTextureData = love.image.newImageData("Ship_1_finish.png")
    shipTexture = love.graphics.newImage(shipTextureData)
    shipTexture:setFilter("nearest", "nearest")

    -- Load cube textures
    cubeTextureData1 = love.image.newImageData("checkered_placeholder.png")
    cubeTexture1 = love.graphics.newImage(cubeTextureData1)
    cubeTexture1:setFilter("nearest", "nearest")

    cubeTextureData2 = love.image.newImageData("checkered_placeholde2r.png")
    cubeTexture2 = love.graphics.newImage(cubeTextureData2)
    cubeTexture2:setFilter("nearest", "nearest")

    print("Textures loaded: Ship " .. shipTexture:getWidth() .. "x" .. shipTexture:getHeight())

    -- Initialize camera
    cam = camera.new(0, 0, -5)
    camera.updateVectors(cam)

    -- Load ship model
    shipModel = obj_loader.load("ship_1.obj")

    -- Create reusable render image
    renderImage = love.graphics.newImage(renderer_dda.getImageData())
    renderImage:setFilter("nearest", "nearest")

    print("Test cube scene loaded successfully")
end

function love.update(dt)
    time = time + dt
    camera.update(cam, dt, 5.0, 2.0)
end

function love.draw()
    -- Clear DDA buffers
    renderer_dda.clearBuffers()

    -- View and projection matrices
    local viewMatrix = camera.getViewMatrix(cam)
    local projectionMatrix = mat4.perspective(
        math.pi / 3,  -- 60 degree FOV
        RENDER_WIDTH / RENDER_HEIGHT,
        0.1,
        100.0
    )

    -- Draw ship model in center
    local modelMatrix = mat4.identity()
    modelMatrix = mat4.multiply(modelMatrix, mat4.rotationY(time))
    modelMatrix = mat4.multiply(modelMatrix, mat4.rotationX(time * 0.7))

    local mvpMatrix = mat4.multiply(projectionMatrix, mat4.multiply(viewMatrix, modelMatrix))
    renderer_dda.setMatrices(mvpMatrix, cam.pos)

    -- Draw all triangles from ship
    for _, tri in ipairs(shipModel.triangles) do
        local v1 = shipModel.vertices[tri[1]]
        local v2 = shipModel.vertices[tri[2]]
        local v3 = shipModel.vertices[tri[3]]
        renderer_dda.drawTriangle3D(v1, v2, v3, texture, textureData)
    end

    -- Draw two test cubes on the sides
    local cubeFaces = {
        {{pos = {-0.5, -0.5,  0.5}, uv = {0, 0}}, {pos = { 0.5, -0.5,  0.5}, uv = {1, 0}}, {pos = { 0.5,  0.5,  0.5}, uv = {1, 1}}, {pos = {-0.5,  0.5,  0.5}, uv = {0, 1}}},
        {{pos = { 0.5, -0.5, -0.5}, uv = {0, 0}}, {pos = {-0.5, -0.5, -0.5}, uv = {1, 0}}, {pos = {-0.5,  0.5, -0.5}, uv = {1, 1}}, {pos = { 0.5,  0.5, -0.5}, uv = {0, 1}}},
        {{pos = {-0.5, -0.5, -0.5}, uv = {0, 0}}, {pos = {-0.5, -0.5,  0.5}, uv = {1, 0}}, {pos = {-0.5,  0.5,  0.5}, uv = {1, 1}}, {pos = {-0.5,  0.5, -0.5}, uv = {0, 1}}},
        {{pos = { 0.5, -0.5,  0.5}, uv = {0, 0}}, {pos = { 0.5, -0.5, -0.5}, uv = {1, 0}}, {pos = { 0.5,  0.5, -0.5}, uv = {1, 1}}, {pos = { 0.5,  0.5,  0.5}, uv = {0, 1}}},
        {{pos = {-0.5,  0.5,  0.5}, uv = {0, 0}}, {pos = { 0.5,  0.5,  0.5}, uv = {1, 0}}, {pos = { 0.5,  0.5, -0.5}, uv = {1, 1}}, {pos = {-0.5,  0.5, -0.5}, uv = {0, 1}}},
        {{pos = {-0.5, -0.5, -0.5}, uv = {0, 0}}, {pos = { 0.5, -0.5, -0.5}, uv = {1, 0}}, {pos = { 0.5, -0.5,  0.5}, uv = {1, 1}}, {pos = {-0.5, -0.5,  0.5}, uv = {0, 1}}},
    }

    for cubeIndex = 1, 2 do
        local xOffset = (cubeIndex == 1) and -3 or 3
        local cubeModelMatrix = mat4.identity()
        cubeModelMatrix = mat4.multiply(cubeModelMatrix, mat4.translation(xOffset, 0, 0))
        cubeModelMatrix = mat4.multiply(cubeModelMatrix, mat4.rotationY(time * 0.5))
        cubeModelMatrix = mat4.multiply(cubeModelMatrix, mat4.rotationX(time * 0.3))

        local cubeMvpMatrix = mat4.multiply(projectionMatrix, mat4.multiply(viewMatrix, cubeModelMatrix))
        renderer_dda.setMatrices(cubeMvpMatrix, cam.pos)

        for _, face in ipairs(cubeFaces) do
            renderer_dda.drawTriangle3D(face[1], face[2], face[3], texture, textureData)
            renderer_dda.drawTriangle3D(face[1], face[3], face[4], texture, textureData)
        end
    end

    -- Update existing image (much faster than creating new one)
    renderImage:replacePixels(renderer_dda.getImageData())

    -- Draw to canvas
    love.graphics.setCanvas(renderCanvas)
    love.graphics.clear(0, 0, 0)
    love.graphics.draw(renderImage, 0, 0)
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

    -- Draw UI
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("FPS: " .. love.timer.getFPS(), 10, 10)
    love.graphics.print("Ship + 2 Cubes - " .. (#shipModel.triangles + 24) .. " triangles", 10, 30)
    love.graphics.print("Camera: " .. string.format("(%.1f, %.1f, %.1f)", cam.pos.x, cam.pos.y, cam.pos.z), 10, 50)
    love.graphics.print("Yaw: " .. string.format("%.2f", cam.yaw) .. " Pitch: " .. string.format("%.2f", cam.pitch), 10, 70)
    love.graphics.print("WASD: Move | Arrows: Look | Space/Shift: Up/Down | ESC: Quit", 10, windowHeight - 30)
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
