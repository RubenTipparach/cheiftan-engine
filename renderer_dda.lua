-- DDA Scanline Software Renderer with LuaJIT FFI optimization
-- Based on reference-lib/Concepts/TwoTriangles.bas

local config = require("config")
local ffi = require("ffi")
local renderer_dda = {}

-- Performance counters
local stats = {
    trianglesDrawn = 0,
    pixelsDrawn = 0,
    trianglesCulled = 0,
    trianglesClipped = 0
}

local RENDER_WIDTH = config.RENDER_WIDTH
local RENDER_HEIGHT = config.RENDER_HEIGHT

-- Buffers
local softwareImageData
local softwareZBuffer
local textureData

-- FFI pointers for direct memory access
local framebufferPtr = nil
local zbufferPtr = nil
local texturePtr = nil
local texWidth = 0
local texHeight = 0

-- Cached matrices for drawTriangle3D
local currentMVP = nil
local currentCamera = nil

function renderer_dda.init(width, height)
    RENDER_WIDTH = width
    RENDER_HEIGHT = height

    -- Initialize software rendering resources
    softwareImageData = love.image.newImageData(RENDER_WIDTH, RENDER_HEIGHT)

    -- Get FFI pointer to framebuffer (RGBA8 format, 4 bytes per pixel)
    framebufferPtr = ffi.cast("uint8_t*", softwareImageData:getFFIPointer())

    -- Allocate z-buffer using FFI for faster access
    zbufferPtr = ffi.new("float[?]", RENDER_WIDTH * RENDER_HEIGHT)
    for i = 0, RENDER_WIDTH * RENDER_HEIGHT - 1 do
        zbufferPtr[i] = math.huge
    end

    print("DDA Renderer initialized (FFI): " .. RENDER_WIDTH .. "x" .. RENDER_HEIGHT)
end

function renderer_dda.clearBuffers()
    -- Auto-initialize if not initialized
    if not zbufferPtr then
        renderer_dda.init(RENDER_WIDTH, RENDER_HEIGHT)
    end

    -- Reset stats
    stats.trianglesDrawn = 0
    stats.pixelsDrawn = 0
    stats.trianglesCulled = 0
    stats.trianglesClipped = 0

    -- Clear z-buffer using FFI (optimized with ffi.fill)
    ffi.fill(zbufferPtr, RENDER_WIDTH * RENDER_HEIGHT * ffi.sizeof("float"), 0x7F)  -- Max float pattern

    -- Clear framebuffer to black (RGBA format) - optimized with ffi.fill
    ffi.fill(framebufferPtr, RENDER_WIDTH * RENDER_HEIGHT * 4, 0)

    -- Set alpha channel to 255
    for i = 3, RENDER_WIDTH * RENDER_HEIGHT * 4 - 1, 4 do
        framebufferPtr[i] = 255
    end
end

function renderer_dda.getStats()
    return stats
end

-- Set pixel with Z-buffer test (FFI optimized)
local function setPixel(x, y, z, r, g, b)
    if x < 0 or x >= RENDER_WIDTH or y < 0 or y >= RENDER_HEIGHT then
        return
    end

    local xi = math.floor(x)
    local yi = math.floor(y)
    local index = yi * RENDER_WIDTH + xi

    if z < zbufferPtr[index] then
        zbufferPtr[index] = z

        -- Write pixel directly to framebuffer (RGBA8)
        local pixelIndex = index * 4
        framebufferPtr[pixelIndex] = r * 255
        framebufferPtr[pixelIndex + 1] = g * 255
        framebufferPtr[pixelIndex + 2] = b * 255
        framebufferPtr[pixelIndex + 3] = 255
    end
end

-- DDA Triangle Rasterization with perspective-correct texture mapping
-- vertex format: {x, y, w, u, v, z}
-- where w = 1/z, u and v are pre-divided by w
function renderer_dda.drawTriangle(vA, vB, vC, texture, texData)
    -- print("  [DDA] drawTriangle called")

    -- Backface culling (cull clockwise/back-facing triangles)
    local edge1x = vB[1] - vA[1]
    local edge1y = vB[2] - vA[2]
    local edge2x = vC[1] - vA[1]
    local edge2y = vC[2] - vA[2]
    local cross = edge1x * edge2y - edge1y * edge2x

    if cross <= 0 then
        stats.trianglesCulled = stats.trianglesCulled + 1
        return  -- Back-facing, skip rendering
    end

    stats.trianglesDrawn = stats.trianglesDrawn + 1

    -- Get texture dimensions and FFI pointer
    local texWidth, texHeight

    -- Handle both Image and ImageData
    if texData then
        -- ImageData was provided
        texWidth = texData:getWidth()
        texHeight = texData:getHeight()

        -- Get FFI pointer to texture data for fast sampling
        texturePtr = ffi.cast("uint8_t*", texData:getFFIPointer())
    elseif texture then
        -- Only Image provided, try to get its data
        texWidth = texture:getWidth()
        texHeight = texture:getHeight()
        -- Cache: use the global textureData if available
        texData = textureData
        if not texData then
            error("renderer_dda.drawTriangle requires ImageData - pass it as 4th parameter")
        end
        texturePtr = ffi.cast("uint8_t*", texData:getFFIPointer())
    else
        error("No texture provided to drawTriangle")
    end

    -- Sort vertices by Y (A=top, B=middle, C=bottom)
    if vB[2] < vA[2] then vA, vB = vB, vA end
    if vC[2] < vA[2] then vA, vC = vC, vA end
    if vC[2] < vB[2] then vB, vC = vC, vB end

    -- Clipping bounds
    local clip_min_y = 0
    local clip_max_y = RENDER_HEIGHT - 1
    local clip_min_x = 0
    local clip_max_x = RENDER_WIDTH

    -- Integer window clipping
    local draw_min_y = math.ceil(vA[2])
    if draw_min_y < clip_min_y then draw_min_y = clip_min_y end

    local draw_max_y = math.ceil(vC[2]) - 1
    if draw_max_y > clip_max_y then draw_max_y = clip_max_y end

    if draw_max_y - draw_min_y < 0 then return end

    -- Calculate deltas for major edge (A to C)
    local delta2_x = vC[1] - vA[1]
    local delta2_y = vC[2] - vA[2]
    local delta2_w = vC[3] - vA[3]
    local delta2_u = vC[4] - vA[4]
    local delta2_v = vC[5] - vA[5]
    local delta2_z = vC[6] - vA[6]

    -- Avoid divide by zero
    if delta2_y < (1 / 256) then return end

    -- Calculate steps for major edge (A to C)
    local legx2_step = delta2_x / delta2_y
    local legw2_step = delta2_w / delta2_y
    local legu2_step = delta2_u / delta2_y
    local legv2_step = delta2_v / delta2_y
    local legz2_step = delta2_z / delta2_y

    -- Calculate deltas for minor edge (A to B initially)
    local delta1_x = vB[1] - vA[1]
    local delta1_y = vB[2] - vA[2]
    local delta1_w = vB[3] - vA[3]
    local delta1_u = vB[4] - vA[4]
    local delta1_v = vB[5] - vA[5]
    local delta1_z = vB[6] - vA[6]

    -- Calculate middle Y where we switch from A-B to B-C
    local draw_middle_y = math.ceil(vB[2])
    if draw_middle_y < clip_min_y then draw_middle_y = clip_min_y end

    -- Calculate steps for minor edge (A to B)
    local legx1_step = 0
    local legw1_step = 0
    local legu1_step = 0
    local legv1_step = 0
    local legz1_step = 0

    if delta1_y > (1 / 256) then
        legx1_step = delta1_x / delta1_y
        legw1_step = delta1_w / delta1_y
        legu1_step = delta1_u / delta1_y
        legv1_step = delta1_v / delta1_y
        legz1_step = delta1_z / delta1_y
    end

    -- Pre-step Y to integer pixel boundary
    local prestep_y1 = draw_min_y - vA[2]

    -- Initialize edge accumulators with pre-stepping
    local leg_x1 = vA[1] + prestep_y1 * legx1_step
    local leg_w1 = vA[3] + prestep_y1 * legw1_step
    local leg_u1 = vA[4] + prestep_y1 * legu1_step
    local leg_v1 = vA[5] + prestep_y1 * legv1_step
    local leg_z1 = vA[6] + prestep_y1 * legz1_step

    local leg_x2 = vA[1] + prestep_y1 * legx2_step
    local leg_w2 = vA[3] + prestep_y1 * legw2_step
    local leg_u2 = vA[4] + prestep_y1 * legu2_step
    local leg_v2 = vA[5] + prestep_y1 * legv2_step
    local leg_z2 = vA[6] + prestep_y1 * legz2_step

    -- Row loop from top to bottom
    local row = draw_min_y
    while row <= draw_max_y do
        -- Declare locals at top of loop to avoid goto scope issues
        local delta_x

        -- Check if we've reached the knee (B vertex)
        if row == draw_middle_y then
            -- Recalculate minor edge from B to C
            delta1_x = vC[1] - vB[1]
            delta1_y = vC[2] - vB[2]
            delta1_w = vC[3] - vB[3]
            delta1_u = vC[4] - vB[4]
            delta1_v = vC[5] - vB[5]
            delta1_z = vC[6] - vB[6]

            if math.abs(delta1_y) < 0.001 then
                goto continue_row
            end

            legx1_step = delta1_x / delta1_y
            legw1_step = delta1_w / delta1_y
            legu1_step = delta1_u / delta1_y
            legv1_step = delta1_v / delta1_y
            legz1_step = delta1_z / delta1_y

            -- Pre-step from B
            local prestep_y2 = draw_middle_y - vB[2]
            leg_x1 = vB[1] + prestep_y2 * legx1_step
            leg_w1 = vB[3] + prestep_y2 * legw1_step
            leg_u1 = vB[4] + prestep_y2 * legu1_step
            leg_v1 = vB[5] + prestep_y2 * legv1_step
            leg_z1 = vB[6] + prestep_y2 * legz1_step
        end

        -- Horizontal scanline
        delta_x = math.abs(leg_x2 - leg_x1)

        if delta_x >= (1 / 2048) then
            local tex_w_step, tex_u_step, tex_v_step, tex_z_step
            local tex_w, tex_u, tex_v, tex_z
            local col, draw_max_x

            -- Determine which edge is left and which is right
            if leg_x1 < leg_x2 then
                -- leg 1 is on the left
                tex_w_step = (leg_w2 - leg_w1) / delta_x
                tex_u_step = (leg_u2 - leg_u1) / delta_x
                tex_v_step = (leg_v2 - leg_v1) / delta_x
                tex_z_step = (leg_z2 - leg_z1) / delta_x

                col = math.ceil(leg_x1)
                if col < clip_min_x then col = clip_min_x end

                -- Pre-step X
                local prestep_x = col - leg_x1
                tex_w = leg_w1 + prestep_x * tex_w_step
                tex_u = leg_u1 + prestep_x * tex_u_step
                tex_v = leg_v1 + prestep_x * tex_v_step
                tex_z = leg_z1 + prestep_x * tex_z_step

                draw_max_x = math.ceil(leg_x2)
                if draw_max_x > clip_max_x then draw_max_x = clip_max_x end
            else
                -- leg 2 is on the left
                tex_w_step = (leg_w1 - leg_w2) / delta_x
                tex_u_step = (leg_u1 - leg_u2) / delta_x
                tex_v_step = (leg_v1 - leg_v2) / delta_x
                tex_z_step = (leg_z1 - leg_z2) / delta_x

                col = math.ceil(leg_x2)
                if col < clip_min_x then col = clip_min_x end

                -- Pre-step X
                local prestep_x = col - leg_x2
                tex_w = leg_w2 + prestep_x * tex_w_step
                tex_u = leg_u2 + prestep_x * tex_u_step
                tex_v = leg_v2 + prestep_x * tex_v_step
                tex_z = leg_z2 + prestep_x * tex_z_step

                draw_max_x = math.ceil(leg_x1)
                if draw_max_x > clip_max_x then draw_max_x = clip_max_x end
            end

            -- Draw horizontal span (FFI optimized)
            while col < draw_max_x do
                -- Recover U and V from perspective-correct interpolation
                local z_recip = 1 / tex_w
                local u = tex_u * z_recip
                local v = tex_v * z_recip

                -- Sample texture with clamping
                local texX = math.floor(u % texWidth)
                local texY = math.floor(v % texHeight)

                if texX < 0 then texX = 0 end
                if texX >= texWidth then texX = texWidth - 1 end
                if texY < 0 then texY = 0 end
                if texY >= texHeight then texY = texHeight - 1 end

                -- Bounds check
                if col >= 0 and col < RENDER_WIDTH and row >= 0 and row < RENDER_HEIGHT then
                    local index = row * RENDER_WIDTH + col

                    -- Z-buffer test
                    if tex_z < zbufferPtr[index] then
                        zbufferPtr[index] = tex_z

                        -- Sample texture using FFI (RGBA format)
                        local texIndex = (texY * texWidth + texX) * 4
                        local r = texturePtr[texIndex]
                        local g = texturePtr[texIndex + 1]
                        local b = texturePtr[texIndex + 2]

                        -- Write to framebuffer
                        local pixelIndex = index * 4
                        framebufferPtr[pixelIndex] = r
                        framebufferPtr[pixelIndex + 1] = g
                        framebufferPtr[pixelIndex + 2] = b
                        framebufferPtr[pixelIndex + 3] = 255

                        stats.pixelsDrawn = stats.pixelsDrawn + 1
                    end
                end

                -- Advance accumulators
                tex_w = tex_w + tex_w_step
                tex_u = tex_u + tex_u_step
                tex_v = tex_v + tex_v_step
                tex_z = tex_z + tex_z_step
                col = col + 1
            end
        end

        ::continue_row::

        -- Step to next row
        leg_x1 = leg_x1 + legx1_step
        leg_w1 = leg_w1 + legw1_step
        leg_u1 = leg_u1 + legu1_step
        leg_v1 = leg_v1 + legv1_step
        leg_z1 = leg_z1 + legz1_step

        leg_x2 = leg_x2 + legx2_step
        leg_w2 = leg_w2 + legw2_step
        leg_u2 = leg_u2 + legu2_step
        leg_v2 = leg_v2 + legv2_step
        leg_z2 = leg_z2 + legz2_step

        row = row + 1
    end
end

function renderer_dda.getImageData()
    return softwareImageData
end

-- Set matrices for 3D rendering
function renderer_dda.setMatrices(mvpMatrix, cameraPos)
    currentMVP = mvpMatrix
    currentCamera = cameraPos
end

-- Linearly interpolate between two vertices at the near plane
local function lerpVertexAtNearPlane(pIn, pOut, vIn, vOut, nearPlane)
    -- Find t where w = nearPlane: pIn[4] + t * (pOut[4] - pIn[4]) = nearPlane
    local t = (nearPlane - pIn[4]) / (pOut[4] - pIn[4])

    -- Lerp clip space position
    local pClip = {
        pIn[1] + t * (pOut[1] - pIn[1]),
        pIn[2] + t * (pOut[2] - pIn[2]),
        pIn[3] + t * (pOut[3] - pIn[3]),
        nearPlane  -- Exactly on the near plane
    }

    -- Lerp UV coordinates
    local vClip = {
        pos = {
            vIn.pos[1] + t * (vOut.pos[1] - vIn.pos[1]),
            vIn.pos[2] + t * (vOut.pos[2] - vIn.pos[2]),
            vIn.pos[3] + t * (vOut.pos[3] - vIn.pos[3])
        },
        uv = {
            vIn.uv[1] + t * (vOut.uv[1] - vIn.uv[1]),
            vIn.uv[2] + t * (vOut.uv[2] - vIn.uv[2])
        }
    }

    return pClip, vClip
end

-- Clips a triangle against the near plane, generating 1 or 2 new triangles
local function clipTriangleNearPlane(p1, p2, p3, v1, v2, v3, n1, n2, n3, nearPlane)
    local clippedTris = {}

    -- Count vertices behind plane
    local behindCount = (n1 and 1 or 0) + (n2 and 1 or 0) + (n3 and 1 or 0)

    if behindCount == 1 then
        -- One vertex behind - split into 2 triangles
        if n1 then
            -- p1 is behind, p2 and p3 are in front
            local pA, vA = lerpVertexAtNearPlane(p2, p1, v2, v1, nearPlane)
            local pB, vB = lerpVertexAtNearPlane(p3, p1, v3, v1, nearPlane)
            table.insert(clippedTris, {p2, p3, pA, v2, v3, vA})
            table.insert(clippedTris, {p3, pB, pA, v3, vB, vA})
        elseif n2 then
            -- p2 is behind, p1 and p3 are in front
            local pA, vA = lerpVertexAtNearPlane(p1, p2, v1, v2, nearPlane)
            local pB, vB = lerpVertexAtNearPlane(p3, p2, v3, v2, nearPlane)
            table.insert(clippedTris, {p1, pA, p3, v1, vA, v3})
            table.insert(clippedTris, {pA, pB, p3, vA, vB, v3})
        else -- n3
            -- p3 is behind, p1 and p2 are in front
            local pA, vA = lerpVertexAtNearPlane(p1, p3, v1, v3, nearPlane)
            local pB, vB = lerpVertexAtNearPlane(p2, p3, v2, v3, nearPlane)
            table.insert(clippedTris, {p1, p2, pA, v1, v2, vA})
            table.insert(clippedTris, {p2, pB, pA, v2, vB, vA})
        end
    elseif behindCount == 2 then
        -- Two vertices behind - create 1 smaller triangle
        if not n1 then
            -- p1 is in front, p2 and p3 are behind
            local pA, vA = lerpVertexAtNearPlane(p1, p2, v1, v2, nearPlane)
            local pB, vB = lerpVertexAtNearPlane(p1, p3, v1, v3, nearPlane)
            table.insert(clippedTris, {p1, pA, pB, v1, vA, vB})
        elseif not n2 then
            -- p2 is in front, p1 and p3 are behind
            local pA, vA = lerpVertexAtNearPlane(p2, p1, v2, v1, nearPlane)
            local pB, vB = lerpVertexAtNearPlane(p2, p3, v2, v3, nearPlane)
            table.insert(clippedTris, {p2, pB, pA, v2, vB, vA})
        else -- not n3
            -- p3 is in front, p1 and p2 are behind
            local pA, vA = lerpVertexAtNearPlane(p3, p1, v3, v1, nearPlane)
            local pB, vB = lerpVertexAtNearPlane(p3, p2, v3, v2, nearPlane)
            table.insert(clippedTris, {p3, pA, pB, v3, vA, vB})
        end
    end

    return clippedTris
end

-- Draw a triangle that's already in clip space (used after clipping)
local function drawClippedTriangle(p1, p2, p3, v1, v2, v3, texture, texData)
    -- Project to screen space
    local s1x = (p1[1] / p1[4] + 1) * RENDER_WIDTH * 0.5
    local s1y = (1 - p1[2] / p1[4]) * RENDER_HEIGHT * 0.5
    local s2x = (p2[1] / p2[4] + 1) * RENDER_WIDTH * 0.5
    local s2y = (1 - p2[2] / p2[4]) * RENDER_HEIGHT * 0.5
    local s3x = (p3[1] / p3[4] + 1) * RENDER_WIDTH * 0.5
    local s3y = (1 - p3[2] / p3[4]) * RENDER_HEIGHT * 0.5

    -- Perspective-correct attributes
    local w1 = 1 / p1[4]
    local w2 = 1 / p2[4]
    local w3 = 1 / p3[4]

    -- Get texture dimensions
    local texW = texData:getWidth()
    local texH = texData:getHeight()

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

    renderer_dda.drawTriangle(vA, vB, vC, texture, texData)
end

-- Draw a triangle in 3D world space
-- v1, v2, v3 are tables with {pos = {x,y,z}, uv = {u,v}}
function renderer_dda.drawTriangle3D(v1, v2, v3, texture, texData)
    if not currentMVP then
        error("Must call renderer_dda.setMatrices() before drawTriangle3D()")
    end

    local mat4 = require("mat4")

    -- Early backface culling in world space (DISABLED - causes issues)
    -- TODO: Fix world-space backface culling math
    -- local edge1x = v2.pos[1] - v1.pos[1]
    -- local edge1y = v2.pos[2] - v1.pos[2]
    -- local edge1z = v2.pos[3] - v1.pos[3]
    -- local edge2x = v3.pos[1] - v1.pos[1]
    -- local edge2y = v3.pos[2] - v1.pos[2]
    -- local edge2z = v3.pos[3] - v1.pos[3]

    -- -- Calculate face normal via cross product
    -- local nx = edge1y * edge2z - edge1z * edge2y
    -- local ny = edge1z * edge2x - edge1x * edge2z
    -- local nz = edge1x * edge2y - edge1y * edge2x

    -- -- View direction from camera to triangle
    -- local centerX = (v1.pos[1] + v2.pos[1] + v3.pos[1]) / 3
    -- local centerY = (v1.pos[2] + v2.pos[2] + v3.pos[2]) / 3
    -- local centerZ = (v1.pos[3] + v2.pos[3] + v3.pos[3]) / 3

    -- if currentCamera then
    --     local viewX = currentCamera.x - centerX
    --     local viewY = currentCamera.y - centerY
    --     local viewZ = currentCamera.z - centerZ

    --     -- Dot product - if negative, backface (normal points away from camera)
    --     local dot = nx * viewX + ny * viewY + nz * viewZ
    --     if dot < 0 then
    --         return
    --     end
    -- end

    -- Transform to clip space
    local p1 = mat4.multiplyVec4(currentMVP, {v1.pos[1], v1.pos[2], v1.pos[3], 1})
    local p2 = mat4.multiplyVec4(currentMVP, {v2.pos[1], v2.pos[2], v2.pos[3], 1})
    local p3 = mat4.multiplyVec4(currentMVP, {v3.pos[1], v3.pos[2], v3.pos[3], 1})

    -- Near plane clipping
    local nearPlane = 0.01
    local n1 = p1[4] <= nearPlane
    local n2 = p2[4] <= nearPlane
    local n3 = p3[4] <= nearPlane

    -- All vertices behind - cull entire triangle
    if n1 and n2 and n3 then
        return
    end

    -- All vertices in front - no clipping needed, continue as normal
    if not (n1 or n2 or n3) then
        -- Continue to projection below
    else
        -- Partial clipping - split triangle
        local clippedTriangles = clipTriangleNearPlane(p1, p2, p3, v1, v2, v3, n1, n2, n3, nearPlane)

        -- Recursively draw clipped triangles
        for _, tri in ipairs(clippedTriangles) do
            -- tri contains {p1, p2, p3, v1, v2, v3} already in clip space
            drawClippedTriangle(tri[1], tri[2], tri[3], tri[4], tri[5], tri[6], texture, texData)
        end
        return
    end

    -- Project to screen space
    local s1x = (p1[1] / p1[4] + 1) * RENDER_WIDTH * 0.5
    local s1y = (1 - p1[2] / p1[4]) * RENDER_HEIGHT * 0.5
    local s2x = (p2[1] / p2[4] + 1) * RENDER_WIDTH * 0.5
    local s2y = (1 - p2[2] / p2[4]) * RENDER_HEIGHT * 0.5
    local s3x = (p3[1] / p3[4] + 1) * RENDER_WIDTH * 0.5
    local s3y = (1 - p3[2] / p3[4]) * RENDER_HEIGHT * 0.5

    -- Perspective-correct attributes
    local w1 = 1 / p1[4]
    local w2 = 1 / p2[4]
    local w3 = 1 / p3[4]

    -- Get texture dimensions
    local texW = texData:getWidth()
    local texH = texData:getHeight()

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

    renderer_dda.drawTriangle(vA, vB, vC, texture, texData)
end

return renderer_dda
