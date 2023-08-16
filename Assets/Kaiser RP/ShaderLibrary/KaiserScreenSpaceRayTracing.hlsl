#ifndef KAISER_SCREEN_SPACE_RAY_TRACING
#define KAISER_SCREEN_SPACE_RAY_TRACING

float rand(float a)
{
    return frac(sin(a * (91.3458)) * 47453.5453);
}

float3 LinearTrace(
    float3 ro, float3 rd, float random, out float3 intersectionPos, out float3 binaryIntersectionPos,
    float rawDepth,
    float4x4 viewProjMatrix,
    Texture2D depthTexture, SamplerState depthTextureSampler
)
{
    bool jitter = true;
    float startingStep = 0.05;
    float stepMult = 1.15;
    const int steps = 40;
    const int binarySteps = 5;

    float maxIntersectionDepthDistance = 1.5;
    float step = startingStep;

    float3 pos = ro;
    float3 p1, p2;
    float3 lastPos = pos;
    bool intersected = false;
    bool possibleIntersection = false;
    float lastRecordedDepthBuffThatIntersected;
    
    intersectionPos = pos;
    binaryIntersectionPos = pos;

    
    for (int i = 0; i < steps; i++)
    {
        float jitter = 0.5 + 0.5 * frac(rand(pos.x + pos.y + pos.z) + random);

        pos = ro + rd * step * jitter;

        float4 projPos = mul(viewProjMatrix, float4(pos, 0.0));
        float2 NDCPos = projPos.xy / projPos.w;
        float2 uvPos = NDCPos * 0.5 + 0.5;

        [branch]
        if (uvPos.x < 0 || uvPos.x > 1 || uvPos.y < 0 || uvPos.y > 1)
        {
            continue;
        }

        float sampleDepth = depthTexture.SampleLevel(depthTextureSampler, uvPos, 0).r;
        float linearEyeDepth = LinearEyeDepth(sampleDepth, _ZBufferParams);

        // [branch]
        // if (sampleDepth == 0.0)
        // {
        //     sampleDepth = 9999999.0;
        // }
        
        // Step 1: Find the first depth buffer sample that intersects the ray

        float deltaDepth = 0;
        [branch]
        if (abs(rawDepth - sampleDepth) > 0 && sampleDepth > 0)
        {
            deltaDepth = pos.z - linearEyeDepth;

            [branch]
            if (deltaDepth > 0)
            {
                possibleIntersection = true;
                lastRecordedDepthBuffThatIntersected = linearEyeDepth;
                p1 = lastPos;
                p2 = pos;
                break;
            }
        }

        lastPos = pos;
        pos += rd * step * (1.0 - jitter);
        step *= stepMult;

        // Step 2: Binary search between p1 and p2 to find the exact intersection point
        intersectionPos = p2;
        binaryIntersectionPos = p2;

        // Step 3: get the intersection point
        [branch]
        if (possibleIntersection && abs(p2.z - lastRecordedDepthBuffThatIntersected) < maxIntersectionDepthDistance) //&& abs(depthAtP2 - lastRecordedDepthBuffThatIntersected) < maxIntersectionDepthDistance)
        {
            intersected = true;
        }
    }

    return intersectionPos;
}




#endif