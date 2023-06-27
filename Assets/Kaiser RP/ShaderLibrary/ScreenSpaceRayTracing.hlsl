#ifndef KAISER_SCREEN_SPACE_RAY_TRACING
#define KAISER_SCREEN_SPACE_RAY_TRACING

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "KaiserStandard.hlsl"

#define RAY_BIAS 0.05f

// SSGI




// SSR
float3x3 GetTangentBasis(float3 TangentZ)
{
    float3 UpVector = abs(TangentZ.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
    float3 TangentX = normalize(cross(UpVector, TangentZ));
    float3 TangentY = cross(TangentZ, TangentX);
    return float3x3(TangentX, TangentY, TangentZ);
}

float3 TangentToWorld_(float3 Vec, float3 TangentZ)
{
    return mul(Vec, GetTangentBasis(TangentZ));
}

float4 TangentToWorld(float3 Vec, float4 TangentZ)
{
    half3 T2W = TangentToWorld_(Vec, TangentZ.rgb);
    return half4(T2W, TangentZ.a);
}

inline float GetScreenFadeBord(float2 pos, float value)
{
    float borderDist = min(1 - max(pos.x, pos.y), min(pos.x, pos.y));
    return saturate(borderDist > value ? 1 : borderDist / value);
}

// Linear Trace

float3 ReconstructCSPosition(float4 _MainTex_TexelSize, float4 _ProjInfo, float2 S, float z)
{
    float linEyeZ = -LinearEyeDepth(z, _ZBufferParams);
    return float3((((S.xy * _MainTex_TexelSize.zw)) * _ProjInfo.xy + _ProjInfo.zw) * linEyeZ, linEyeZ);
}

float3 GetPosition(TEXTURE2D(depth), SamplerState depthSampler, float4 _MainTex_TexelSize, float4 _ProjInfo, float2 ssP)
{
    float3 P;
    // P.z = SAMPLE_DEPTH_TEXTURE(depth, depthSampler, ssP.xy).r;
    P.z = depth.SampleLevel(depthSampler, ssP.xy, 0).r;
    P = ReconstructCSPosition(_MainTex_TexelSize, _ProjInfo, float2(ssP), P.z);
    return P;
}

inline float distanceSquared(float2 A, float2 B)
{
    A -= B;
    return dot(A, A);
}

inline float distanceSquared(float3 A, float3 B)
{
    A -= B;
    return dot(A, A);
}

void swap(inout float v0, inout float v1)
{
    float temp = v0;
    v0 = v1;
    v1 = temp;
}

bool intersectsDepthBuffer(float rayZMin, float rayZMax, float sceneZ, float layerThickness)
{
    return (rayZMax >= sceneZ - layerThickness) && (rayZMin <= sceneZ);
}

void rayIterations(TEXTURE2D(frontDepth),
SamplerState sampler_frontDepth,
in bool traceBehind_Old,
in bool traceBehind,
inout float2 P,
inout float stepDirection,
inout float end,
inout int stepCount,
inout int maxSteps,
inout bool intersecting,
inout float sceneZ,
inout float2 dP,
inout float3 Q,
inout float3 dQ,
inout float k,
inout float dk,
inout float rayZMin,
inout float rayZMax,
inout float prevZMaxEstimate,
inout bool permute,
inout float2 hitPixel,
float2 invSize,
inout float layerThickness)
{
    bool stop = intersecting;
    for (; (P.x * stepDirection) <= end && stepCount < maxSteps && !stop; P += dP, Q.z += dQ.z, k += dk, stepCount += 1)
    {
        rayZMin = prevZMaxEstimate;
        rayZMax = (dQ.z * 0.5 + Q.z) / (dk * 0.5 + k);
        prevZMaxEstimate = rayZMax;

        if (rayZMin > rayZMax)
        {
            swap(rayZMin, rayZMax);
        }

        hitPixel = permute ? P.yx : P;
        sceneZ = SAMPLE_TEXTURE2D_LOD(frontDepth, sampler_frontDepth, float2(hitPixel * invSize), 0).r;
        sceneZ = -LinearEyeDepth(sceneZ, _ZBufferParams);
        bool isBehind = (rayZMin <= sceneZ);

        if (traceBehind_Old == 1)
        {
            intersecting = isBehind && (rayZMax >= sceneZ - layerThickness);
        }
        else
        {
            intersecting = (rayZMax >= sceneZ - layerThickness);
        }

        stop = traceBehind ? intersecting : isBehind;
    }
    P -= dP, Q.z -= dQ.z, k -= dk;
}

bool Linear2D_Trace(TEXTURE2D(frontDepth),
SamplerState sampler_frontDepth,
float3 csOrigin,
float3 csDirection,
float4x4 projectMatrix,
float2 csZBufferSize,
float jitter,
int maxSteps,
float layerThickness,
float traceDistance,
in out float2 hitPixel,
int stepSize,
bool traceBehind,
in out float3 csHitPoint,
in out float stepCount)
{

    float2 invSize = float2(1 / csZBufferSize.x, 1 / csZBufferSize.y);
    hitPixel = float2(-1, -1);

    float nearPlaneZ = -0.01;
    float rayLength = ((csOrigin.z + csDirection.z * traceDistance) > nearPlaneZ) ? ((nearPlaneZ - csOrigin.z) / csDirection.z) : traceDistance;
    float3 csEndPoint = csDirection * rayLength + csOrigin;
    float4 H0 = mul(projectMatrix, float4(csOrigin, 1));
    float4 H1 = mul(projectMatrix, float4(csEndPoint, 1));
    float k0 = 1 / H0.w;
    float k1 = 1 / H1.w;
    float2 P0 = H0.xy * k0;
    float2 P1 = H1.xy * k1;
    float3 Q0 = csOrigin * k0;
    float3 Q1 = csEndPoint * k1;

    float yMax = csZBufferSize.y - 0.5;
    float yMin = 0.5;
    float xMax = csZBufferSize.x - 0.5;
    float xMin = 0.5;
    float alpha = 0;

    if (P1.y > yMax || P1.y < yMin)
    {
        float yClip = (P1.y > yMax) ? yMax : yMin;
        float yAlpha = (P1.y - yClip) / (P1.y - P0.y);
        alpha = yAlpha;
    }
    if (P1.x > xMax || P1.x < xMin)
    {
        float xClip = (P1.x > xMax) ? xMax : xMin;
        float xAlpha = (P1.x - xClip) / (P1.x - P0.x);
        alpha = max(alpha, xAlpha);
    }

    P1 = lerp(P1, P0, alpha);
    k1 = lerp(k1, k0, alpha);
    Q1 = lerp(Q1, Q0, alpha);

    P1 = (distanceSquared(P0, P1) < 0.0001) ? P0 + float2(0.01, 0.01) : P1;
    float2 delta = P1 - P0;
    bool permute = false;

    if (abs(delta.x) < abs(delta.y))
    {
        permute = true;
        delta = delta.yx;
        P1 = P1.yx;
        P0 = P0.yx;
    }

    float stepDirection = sign(delta.x);
    float invdx = stepDirection / delta.x;
    float2 dP = float2(stepDirection, invdx * delta.y);
    float3 dQ = (Q1 - Q0) * invdx;
    float dk = (k1 - k0) * invdx;

    dP *= stepSize;
    dQ *= stepSize;
    dk *= stepSize;
    P0 += dP * jitter;
    Q0 += dQ * jitter;
    k0 += dk * jitter;

    float3 Q = Q0;
    float k = k0;
    float prevZMaxEstimate = csOrigin.z;
    stepCount = 0;
    float rayZMax = prevZMaxEstimate, rayZMin = prevZMaxEstimate;
    float sceneZ = 100000;
    float end = P1.x * stepDirection;
    bool intersecting = intersectsDepthBuffer(rayZMin, rayZMax, sceneZ, layerThickness);
    float2 P = P0;
    int originalStepCount = 0;

    bool traceBehind_Old = true;
    rayIterations(frontDepth, sampler_frontDepth, traceBehind_Old, traceBehind, P, stepDirection, end, originalStepCount, maxSteps, intersecting, sceneZ, dP, Q, dQ, k, dk, rayZMin, rayZMax, prevZMaxEstimate, permute, hitPixel, invSize, layerThickness);

    stepCount = originalStepCount;
    Q.xy += dQ.xy * stepCount;
    csHitPoint = Q * (1 / k);
    return intersecting;
}



float3 intersectDepth_Plane(float3 rayOrigin, float3 rayDir, float marchSize)
{
    return rayOrigin + rayDir * marchSize;
}

float2 cell(float2 ray, float2 cell_count)
{
    return floor(ray.xy * cell_count);
}

float2 cell_count(float level, float2 ScreenSize)
{
    return ScreenSize / (level == 0 ? 1 : exp2(level));
}

float3 intersect_cell_boundary(float3 rayOrigin, float3 rayDir, float2 cellIndex, float2 cellCount, float2 crossStep, float2 crossOffset)
{
    float2 cell_size = 1.0 / cellCount;
    float2 planes = cellIndex / cellCount + cell_size * crossStep;

    float2 solutions = (planes - rayOrigin.xy) / rayDir.xy;
    float3 intersection_pos = rayOrigin + rayDir * min(solutions.x, solutions.y);

    intersection_pos.xy += (solutions.x < solutions.y) ? float2(crossOffset.x, 0.0) : float2(0.0, crossOffset.y);

    return intersection_pos;
}

bool crossed_cell_boundary(float2 cell_id_one, float2 cell_id_two)
{
    return (int)cell_id_one.x != (int)cell_id_two.x || (int)cell_id_one.y != (int)cell_id_two.y;
}

float minimum_depth_plane(float2 ray, float level, float2 cell_count, Texture2D SceneDepth)
{
    return -SceneDepth.Load(float3(ray * cell_count, level)).r;
}

float4 Hierarchical_Z_Trace(int HiZ_Max_Level, int HiZ_Start_Level, int HiZ_Stop_Level, int NumSteps, float Thickness, float2 screenSize, float3 rayOrigin, float3 rayDir, Texture2D SceneDepth)
{
    HiZ_Max_Level = clamp(HiZ_Max_Level, 0.0, 7.0);
    rayOrigin = half3(rayOrigin.x, rayOrigin.y, -rayOrigin.z); rayDir = half3(rayDir.x, rayDir.y, -rayDir.z);

    float level = HiZ_Start_Level; float3 ray = rayOrigin;

    float2 cross_step = float2(rayDir.x >= 0.0 ? 1.0 : - 1.0, rayDir.y >= 0.0 ? 1.0 : - 1.0);
    float2 cross_offset = cross_step * 0.00001;
    cross_step = saturate(cross_step);

    float2 hi_z_size = cell_count(level, screenSize);
    float2 ray_cell = cell(ray.xy, hi_z_size.xy);
    ray = intersect_cell_boundary(ray, rayDir, ray_cell, hi_z_size, cross_step, cross_offset);

    int iterations = 0.0; float mask = 1.0;
    while (level >= HiZ_Stop_Level && iterations < NumSteps)
    {
        float3 tmp_ray = ray;
        float2 current_cell_count = cell_count(level, screenSize);
        float2 old_cell_id = cell(ray.xy, current_cell_count);
        float min_z = minimum_depth_plane(ray.xy, level, current_cell_count, SceneDepth);

        if (rayDir.z > 0)
        {
            float min_minus_ray = min_z - ray.z;
            tmp_ray = min_minus_ray > 0 ? ray + (rayDir / rayDir.z) * min_minus_ray : tmp_ray;
            float2 new_cell_id = cell(tmp_ray.xy, current_cell_count);
            
            if (crossed_cell_boundary(old_cell_id, new_cell_id))
            {
                tmp_ray = intersect_cell_boundary(ray, rayDir, old_cell_id, current_cell_count, cross_step, cross_offset);
                level = min(HiZ_Max_Level, level + 2.0);
            }
            // else {
            //         if(level == 1.0 && abs(min_minus_ray) > 0.0001) {
            //             tmp_ray = intersect_cell_boundary(ray, rayDir, old_cell_id, current_cell_count, cross_step, cross_offset);
            //             level = 2.0;
            //         }
            // }

        }
        else if (ray.z < min_z)
        {
            tmp_ray = intersect_cell_boundary(ray, rayDir, old_cell_id, current_cell_count, cross_step, cross_offset);
            level = min(HiZ_Max_Level, level + 2.0);
        }

        ray.xyz = tmp_ray.xyz;
        level--;
        iterations++;

        mask = (-LinearEyeDepth(-min_z, _ZBufferParams)) - (-LinearEyeDepth(-ray.z, _ZBufferParams)) < Thickness && iterations > 0.0;
    }

    return half4(ray.xy, -ray.z, mask);
}

float GetEdgeStoppNormalWeight(float3 normal_p, float3 normal_q, float sigma)
{
    return pow(max(dot(normal_p, normal_q), 0.0), sigma);
}

float GetEdgeStopDepthWeight(float x, float m, float sigma)
{
    float a = length(x - m) / sigma;
    a *= a;
    return exp(-0.5 * a);
}




#endif