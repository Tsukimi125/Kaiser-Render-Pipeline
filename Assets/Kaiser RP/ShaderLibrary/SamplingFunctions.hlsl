#ifndef KAISER_SAMPLE
#define KAISER_SAMPLE

#define Pi 3.1416

float2 Hammersley16(uint Index, uint NumSamples, uint2 Random)
{
    float E1 = frac((float)Index / NumSamples + float(Random.x) * (1.0 / 65536.0));
    float E2 = float((ReverseBits32(Index) >> 16) ^ Random.y) * (1.0 / 65536.0);
    return float2(E1, E2);
}


float2 UniformSampleDiskConcentric(float2 E)
{
    float2 p = 2 * E - 1;
    float Radius;
    float Phi;
    if (abs(p.x) > abs(p.y))
    {
        Radius = p.x;
        Phi = (PI / 4) * (p.y / p.x);
    }
    else
    {
        Radius = p.y;
        Phi = (PI / 2) - (PI / 4) * (p.x / p.y);
    }
    return float2(Radius * cos(Phi), Radius * sin(Phi));
}



float4 CosineSampleHemisphere(float2 E)
{
    float Phi = 2 * Pi * E.x;
    float CosTheta = sqrt(E.y);
    float SinTheta = sqrt(1 - CosTheta * CosTheta);

    float3 H;
    H.x = SinTheta * cos(Phi);
    H.y = SinTheta * sin(Phi);
    H.z = CosTheta;

    float PDF = CosTheta / Pi;
    return float4(H, PDF);
}

float4 ImportanceSampleGGX(float2 E, float Roughness)
{
    float m = Roughness * Roughness;
    float m2 = m * m;

    float Phi = 2 * Pi * E.x;
    float CosTheta = sqrt((1 - E.y) / (1 + (m2 - 1) * E.y));
    float SinTheta = sqrt(1 - CosTheta * CosTheta);

    float3 H;
    H.x = SinTheta * cos(Phi);
    H.y = SinTheta * sin(Phi);
    H.z = CosTheta;
    
    float d = (CosTheta * m2 - CosTheta) * CosTheta + 1;
    float D = m2 / (Pi * d * d);
    
    float PDF = D * CosTheta;
    return float4(H, PDF);
}

#endif