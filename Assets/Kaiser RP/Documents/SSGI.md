# Screen Space Global Illumination

## 介绍

SSGI是一种基于屏幕空间的全局光照技术，它可以在不需要额外的光照贴图的情况下实现全局光照效果。它的原理是通过在屏幕空间对光照进行采样，然后将采样结果与场景中的物体进行混合，从而实现全局光照效果。

## 步骤

1. 根据场景depth获取Hiz-depth
2. 根据场景颜色、Hiz-depth做屏幕空间的Hiz-trace，得到GI color
3. 将GI color进行空间降噪
4. 将GI color进行时间降噪（可选）
5. 将GI color与场景中的颜色进行混合



