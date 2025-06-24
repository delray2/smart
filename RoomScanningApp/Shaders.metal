#include <metal_stdlib>
using namespace metal;

// Basic vertex shader for AR rendering
vertex float4 basic_vertex_main(const device float3* positions [[buffer(0)]],
                               uint vid [[vertex_id]]) {
    return float4(positions[vid], 1.0);
}

// Basic fragment shader for AR rendering
fragment float4 basic_fragment_main() {
    return float4(1.0, 1.0, 1.0, 1.0);
}

// Shader for room scanning visualization
vertex float4 room_scan_vertex_main(const device float3* positions [[buffer(0)]],
                                   const device float3* normals [[buffer(1)]],
                                   constant float4x4& modelViewProjectionMatrix [[buffer(2)]],
                                   uint vid [[vertex_id]]) {
    float3 position = positions[vid];
    float3 normal = normals[vid];
    
    float4 worldPosition = modelViewProjectionMatrix * float4(position, 1.0);
    return worldPosition;
}

fragment float4 room_scan_fragment_main(const float3 worldNormal [[stage_in]]) {
    float3 normal = normalize(worldNormal);
    float3 lightDirection = normalize(float3(1.0, 1.0, 1.0));
    float diffuse = max(dot(normal, lightDirection), 0.0);
    
    return float4(diffuse, diffuse, diffuse, 1.0);
} 