-- Unified camera system for all scenes

local vec3 = require("vec3")
local mat4 = require("mat4")

local camera = {}

function camera.new(x, y, z)
    return {
        pos = vec3.new(x or 0, y or 0, z or 0),
        pitch = 0,  -- X rotation
        yaw = 0,    -- Y rotation
        forward = vec3.new(0, 0, 1),
        right = vec3.new(1, 0, 0),
        up = vec3.new(0, 1, 0)
    }
end

-- Update camera direction vectors based on pitch/yaw
function camera.updateVectors(cam)
    local cy = math.cos(cam.yaw)
    local sy = math.sin(cam.yaw)
    local cp = math.cos(cam.pitch)
    local sp = math.sin(cam.pitch)

    cam.forward = vec3.new(
        sy * cp,
        -sp,
        cy * cp
    )

    local worldUp = vec3.new(0, 1, 0)
    cam.right = vec3.normalize(vec3.cross(cam.forward, worldUp))
    cam.up = vec3.cross(cam.right, cam.forward)
end

-- Build view matrix from camera
function camera.getViewMatrix(cam)
    local viewMatrix = mat4.identity()
    viewMatrix = mat4.multiply(viewMatrix, mat4.rotationX(-cam.pitch))
    viewMatrix = mat4.multiply(viewMatrix, mat4.rotationY(-cam.yaw))
    viewMatrix = mat4.multiply(viewMatrix, mat4.translation(-cam.pos.x, -cam.pos.y, -cam.pos.z))
    return viewMatrix
end

-- Handle camera input (call from love.update)
function camera.update(cam, dt, moveSpeed, rotSpeed)
    moveSpeed = moveSpeed or 5.0
    rotSpeed = rotSpeed or 2.0

    -- Rotation with arrow keys (inverted left/right)
    if love.keyboard.isDown("left") then
        cam.yaw = cam.yaw + rotSpeed * dt
        camera.updateVectors(cam)
    end
    if love.keyboard.isDown("right") then
        cam.yaw = cam.yaw - rotSpeed * dt
        camera.updateVectors(cam)
    end
    if love.keyboard.isDown("up") then
        cam.pitch = cam.pitch + rotSpeed * dt
        camera.updateVectors(cam)
    end
    if love.keyboard.isDown("down") then
        cam.pitch = cam.pitch - rotSpeed * dt
        camera.updateVectors(cam)
    end

    -- Movement with WASD
    if love.keyboard.isDown("w") then
        cam.pos = vec3.sub(cam.pos, vec3.scale(cam.forward, moveSpeed * dt))
    end
    if love.keyboard.isDown("s") then
        cam.pos = vec3.add(cam.pos, vec3.scale(cam.forward, moveSpeed * dt))
    end
    if love.keyboard.isDown("a") then
        cam.pos = vec3.add(cam.pos, vec3.scale(cam.right, moveSpeed * dt))
    end
    if love.keyboard.isDown("d") then
        cam.pos = vec3.sub(cam.pos, vec3.scale(cam.right, moveSpeed * dt))
    end
    if love.keyboard.isDown("space") then
        cam.pos = vec3.add(cam.pos, vec3.scale(cam.up, moveSpeed * dt))
    end
    if love.keyboard.isDown("lshift") then
        cam.pos = vec3.sub(cam.pos, vec3.scale(cam.up, moveSpeed * dt))
    end
end

return camera
