#include <metal_stdlib>
using namespace metal;

// Vertex input structure
struct VertexInput {
    float4 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

// Vertex output structure (passed to fragment shader)
struct VertexOutput {
    float4 position [[position]];
    float4 color;
};

// Vertex shader function
vertex VertexOutput vertexShader(VertexInput in [[stage_in]],
                               constant float4x4 &modelViewProjection [[buffer(1)]]) {
    VertexOutput out;
    
    // Transform position to clip space
    out.position = modelViewProjection * in.position;
    
    // Pass color through to fragment shader
    out.color = in.color;
    
    return out;
}

// Fragment shader function
fragment float4 fragmentShader(VertexOutput in [[stage_in]]) {
    // Output the interpolated color
    return in.color;
}

// Simple shader to render a texture
vertex VertexOutput textureVertexShader(VertexInput in [[stage_in]]) {
    VertexOutput out;
    
    // For texture rendering, we use the position directly (assuming it's already in clip space)
    out.position = in.position;
    
    // Pass color through to fragment shader
    out.color = in.color;
    
    return out;
}

// Fragment shader for texture rendering
fragment float4 textureFragmentShader(VertexOutput in [[stage_in]],
                                    texture2d<float> texture [[texture(0)]],
                                    sampler textureSampler [[sampler(0)]]) {
    // Sample the texture
    float2 texCoord = float2((in.position.x + 1.0) * 0.5, (in.position.y + 1.0) * 0.5);
    float4 textureColor = texture.sample(textureSampler, texCoord);
    
    // Mix with the vertex color
    return textureColor * in.color;
}

