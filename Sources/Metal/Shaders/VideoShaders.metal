#include <metal_stdlib>
using namespace metal;

// Structure for vertex inputs for video rendering
struct VideoVertexInput {
    float4 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

// Structure for output from the vertex shader
struct VideoVertexOutput {
    float4 position [[position]];
    float2 texCoord;
};

// Parameters for controlling morphing effects
struct MorphingUniforms {
    float morphAmount;      // 0.0 - 1.0: overall intensity of the effect
    float morphType;        // Determines which effect to use
    float time;             // For time-based animations
    float2 touchPosition;   // For user interaction with effects
    float4 extraParams;     // Additional effect-specific parameters
};

// Constants for effect types
constant int EFFECT_NONE = 0;
constant int EFFECT_WAVE = 1;
constant int EFFECT_PIXELATE = 2;
constant int EFFECT_SWIRL = 3;
constant int EFFECT_BULGE = 4;
constant int EFFECT_KALEIDOSCOPE = 5;

//
// VERTEX SHADERS
//

// Basic vertex shader for rendering video to a quad
vertex VideoVertexOutput videoVertexShader(VideoVertexInput in [[stage_in]]) {
    VideoVertexOutput out;
    out.position = in.position;
    out.texCoord = in.texCoord;
    return out;
}

//
// FRAGMENT SHADERS
//

// Basic fragment shader that samples from a video texture
fragment float4 videoSamplingFragmentShader(VideoVertexOutput in [[stage_in]],
                                           texture2d<float> videoTexture [[texture(0)]],
                                           sampler textureSampler [[sampler(0)]]) {
    float4 color = videoTexture.sample(textureSampler, in.texCoord);
    return color;
}

// Helper function to apply wave distortion
float2 applyWaveEffect(float2 texCoord, float time, float amount) {
    float2 offset;
    offset.x = sin(texCoord.y * 10.0 + time) * 0.01 * amount;
    offset.y = sin(texCoord.x * 10.0 + time) * 0.01 * amount;
    return texCoord + offset;
}

// Helper function to apply pixelation
float2 applyPixelateEffect(float2 texCoord, float amount) {
    float blockSize = max(0.002, amount * 0.05);
    float2 blocks = floor(texCoord / blockSize) * blockSize;
    return blocks + blockSize/2.0;
}

// Helper function to apply swirl effect
float2 applySwirlEffect(float2 texCoord, float2 center, float amount, float time) {
    float2 centered = texCoord - center;
    float distance = length(centered);
    float angle = atan2(centered.y, centered.x);
    angle += distance * amount * sin(time * 0.5) * 10.0;
    
    float2 result;
    result.x = center.x + cos(angle) * distance;
    result.y = center.y + sin(angle) * distance;
    return result;
}

// Helper function to apply bulge/pinch effect
float2 applyBulgeEffect(float2 texCoord, float2 center, float amount) {
    float2 centered = texCoord - center;
    float distance = length(centered);
    float scaleFactor = mix(1.0, 1.0 - distance * 2.0, amount);
    
    return center + centered * scaleFactor;
}

// Helper function to apply kaleidoscope effect
float2 applyKaleidoscopeEffect(float2 texCoord, float2 center, float segments, float amount) {
    float2 centered = texCoord - center;
    float angle = atan2(centered.y, centered.x);
    float distance = length(centered);
    
    // Divide into segments
    float segmentAngle = 3.14159265359 * 2.0 / segments;
    angle = mod(angle, segmentAngle);
    
    // Mirror every other segment
    if (mod(floor(angle / segmentAngle), 2.0) >= 1.0) {
        angle = segmentAngle - angle;
    }
    
    float2 result;
    result.x = center.x + cos(angle) * distance;
    result.y = center.y + sin(angle) * distance;
    
    return mix(texCoord, result, amount);
}

// Main morphing fragment shader that combines multiple effects
fragment float4 morphingFragmentShader(VideoVertexOutput in [[stage_in]],
                                     texture2d<float> videoTexture [[texture(0)]],
                                     sampler textureSampler [[sampler(0)]],
                                     constant MorphingUniforms &uniforms [[buffer(0)]]) {
    // Start with the original texture coordinates
    float2 texCoord = in.texCoord;
    float effectType = uniforms.morphType;
    float amount = uniforms.morphAmount;
    float time = uniforms.time;
    float2 center = float2(0.5, 0.5); // Default to center of screen
    
    // If touch position is provided, use it as center
    if (uniforms.touchPosition.x > 0.0 || uniforms.touchPosition.y > 0.0) {
        center = uniforms.touchPosition;
    }
    
    // Apply the selected effect based on morphType
    if (effectType >= 0.5 && effectType < 1.5) {
        // Wave effect
        texCoord = applyWaveEffect(texCoord, time, amount);
    } else if (effectType >= 1.5 && effectType < 2.5) {
        // Pixelate effect
        texCoord = applyPixelateEffect(texCoord, amount);
    } else if (effectType >= 2.5 && effectType < 3.5) {
        // Swirl effect
        texCoord = applySwirlEffect(texCoord, center, amount, time);
    } else if (effectType >= 3.5 && effectType < 4.5) {
        // Bulge effect
        texCoord = applyBulgeEffect(texCoord, center, amount);
    } else if (effectType >= 4.5 && effectType < 5.5) {
        // Kaleidoscope effect
        texCoord = applyKaleidoscopeEffect(texCoord, center, uniforms.extraParams.x * 10.0, amount);
    }
    
    // Ensure texture coordinates stay within bounds
    texCoord = clamp(texCoord, float2(0.0, 0.0), float2(1.0, 1.0));
    
    // Sample from the video texture with our modified coordinates
    float4 color = videoTexture.sample(textureSampler, texCoord);
    
    // Apply any additional color transformations if needed
    if (uniforms.extraParams.y > 0.5) {
        // Example: Apply color transformations based on extra parameters
        // Convert to grayscale with controllable amount
        float grayscale = (color.r + color.g + color.b) / 3.0;
        color.rgb = mix(color.rgb, float3(grayscale), uniforms.extraParams.z);
    }
    
    return color;
}

// Visualization fragment shader for control points (if needed for UI)
fragment float4 controlPointFragmentShader(VideoVertexOutput in [[stage_in]],
                                         constant MorphingUniforms &uniforms [[buffer(0)]]) {
    float2 center = uniforms.touchPosition;
    float dist = distance(in.texCoord, center);
    
    // Draw a simple circular control point
    if (dist < 0.01) {
        return float4(1.0, 0.0, 0.0, 1.0); // Red dot
    } else if (dist < 0.015) {
        return float4(1.0, 1.0, 1.0, 1.0); // White outline
    }
    
    // Transparent elsewhere
    return float4(0.0, 0.0, 0.0, 0.0);
}

