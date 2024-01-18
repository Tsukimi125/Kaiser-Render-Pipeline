using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class RandomSampler
{
    public int frameIndex = 0;
    public int sampleCount = 64;

    public RandomSampler(int frameIndex, int sampleCount)
    {
        this.frameIndex = frameIndex;
        this.sampleCount = sampleCount;
    }
    public Vector2 randomVector2
    {
        get
        {
            return new Vector2(GetHaltonValue(frameIndex & 1023, 2), GetHaltonValue(frameIndex & 1023, 3));
        }
    }


    public void RefreshFrame()
    {
        if (frameIndex++ >= sampleCount)
            frameIndex = 0;
    }

    private float GetHaltonValue(int index, int radix)
    {
        float result = 0f;
        float fraction = 1f / radix;

        while (index > 0)
        {
            result += (index % radix) * fraction;
            index /= radix;
            fraction /= radix;
        }
        return result;
    }
    public Vector2 GetRandomOffset()
    {
        return new Vector2(GetHaltonValue(frameIndex & 1023, 2), GetHaltonValue(frameIndex & 1023, 3));
    }
}
