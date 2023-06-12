using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;


[System.Serializable]
public class PyramidDepthSettings
{
    // Pass在渲染管线中的执行位置，这里设置为【BeforeRenderingPostProcessing】
    public ComputeShader computeShader; //所用ComputeShader

    public int mipCount = 7; //金字塔层数

    public bool debugEnabled = false; //是否开启Debug模式


    [Range(0, 7)]
    public int debugMip = 0; //Debug模式下所显示的MipLevel
}