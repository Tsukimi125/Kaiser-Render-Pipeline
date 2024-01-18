using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;


public class KaiserUtils : MonoBehaviour
{
    // Start is called before the first frame update
    // public static void EnsureRenderTarget(ref RenderTexture rt, int width, int height, RenderTextureFormat format, FilterMode filterMode, int depthBits = 0, int antiAliasing = 1)
    // {
    //     if (rt != null && (rt.width != width || rt.height != height || rt.format != format || rt.filterMode != filterMode || rt.antiAliasing != antiAliasing))
    //     {
    //         RenderTexture.ReleaseTemporary(rt);
    //         rt = null;
    //     }
    //     if (rt == null)
    //     {
    //         rt = RenderTexture.GetTemporary(width, height, depthBits, format, RenderTextureReadWrite.Default, antiAliasing);
    //         rt.filterMode = filterMode;
    //         rt.wrapMode = TextureWrapMode.Clamp;
    //     }
    // }
    // public static void EnsureRenderTargetId(ref RenderTargetIdentifier id, int width, int height, RenderTextureFormat format, FilterMode filterMode, int depthBits = 0, int antiAliasing = 1)
    // {
    //     if (rt != null && (rt.width != width || rt.height != height || rt.format != format || rt.filterMode != filterMode || rt.antiAliasing != antiAliasing))
    //     {
    //         RenderTexture.ReleaseTemporary(rt);
    //         rt = null;
    //     }
    //     if (rt == null)
    //     {
    //         rt = RenderTexture.GetTemporary(width, height, depthBits, format, RenderTextureReadWrite.Default, antiAliasing);
    //         rt.filterMode = filterMode;
    //         rt.wrapMode = TextureWrapMode.Clamp;
    //     }
    // }
}
