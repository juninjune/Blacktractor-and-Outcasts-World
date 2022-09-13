// SkyProbe Fog by Silent
// version 2

// Based off Distance Fade Cube Volume
// by Neitri, free of charge, free to redistribute
// from https://github.com/netri/Neitri-Unity-Shaders

Shader "Silent/SkyProbe Fog/Height"
{
    Properties
    {
        [Header(Make sure you assign a probe as anchor override)]
        [Header(or set Reflection Probes to Simple.)]
        [Space]
        [Header(Base)]
        _Color("Color Tint", Color) = (0,0,0,1)
        _BlurLevel("Blur Level (def: 4)", Range(0, 7)) = 4

        [Header(Fog)]
        [Gamma]_FogStrengthA("Fog Density", Range(0.001, 1)) = .2
        [Gamma]_FogStrengthB ("Fog Height", Range(0.001, 1)) = .5
        [Space]
        [ToggleUI]_ApplyClip ("Don't apply to foreground", Float) = 0.0
        [ToggleUI]_ApplySkybox ("Don't apply to skybox", Float) = 0.0
        [Space]
        _SunSize ("Sun Size", Range(0, 1)) = 0.04

        [Header(Clouds)]
        [Toggle(_NORMALMAP)]_UseClouds("Enable Clouds", Float) = 0
        _CloudNoiseTexture("Cloud Noise Texture", 2D) = "grey" {}
        [HDR]_CloudDirection("Cloud Scale", Vector) = (.1, .1, .1, .1)
        [HDR]_CloudMovement("Cloud Movement", Vector) = (1, 1, 1, .1)
        _CloudStrength("Cloud Strength", Range(0, 10)) = 1
        _CloudDither("Cloud Dithering", Range(0, 1)) = 0

        [Header(System)]
        [Enum(UnityEngine.Rendering.CullMode)] _CullMode("Cull Mode", Float) = 0

        [Enum(UnityEngine.Rendering.BlendMode)]
        _SrcBlend("Src Factor", Float) = 5  // SrcAlpha
        [Enum(UnityEngine.Rendering.BlendMode)]
        _DstBlend("Dst Factor", Float) = 10 // OneMinusSrcAlpha
        [Space]
        [Toggle(BLOOM)]_NoPremultiplyAlpha("Don't premultiply alpha", Float) = 0.0
    }
    SubShader
    {
        Tags
        {
            "Queue" = "Transparent-216"
            "RenderType" = "Custom"
            "ForceNoShadowCasting"="True" 
            "IgnoreProjector"="True"
            "DisableBatching"="True"
        }

        ZWrite Off
        ZTest Always
        Cull[_CullMode]
        Blend[_SrcBlend][_DstBlend]

        Pass
        {
            Lighting On
            Tags
            {
                "LightMode" = "Always"
            }
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma target 3.0

            #pragma multi_compile_instancing
            // #pragma multi_compile_fwdbase nolightmap nodynlightmap novertexlight
            // #pragma multi_compile_fwdadd_fullshadows

            #include "UnityCG.cginc"
            #include "AutoLight.cginc"
            #include "Lighting.cginc"

            #if defined(SHADER_API_D3D11) || defined(SHADER_API_XBOXONE) || defined(UNITY_COMPILER_HLSLCC)//ASE Sampler Macros
            #define UNITY_SAMPLE_TEX2D_LOD(tex,coord,lod) tex.SampleLevel (sampler##tex,coord, lod)
            #else
            #define UNITY_SAMPLE_TEX2D_LOD(tex,coord,lod) tex2Dlod(tex,float4(coord,0,lod))
            #endif

            #pragma shader_feature _ BLOOM
            #pragma shader_feature _ _NORMALMAP

            #define _PREMULTIPLY defined(BLOOM)
            #define _CLOUDS defined(_NORMALMAP)

            float4 _Color;
            float4 _LightScaleOffset;
            float4 _CloudDirection;
            float4 _CloudMovement;
            float _FadeFalloff;
            float _ApplyClip;
            float _ApplySkybox;
            float _FogStrengthB;
            float _FogStrengthA;
            float _SunSize;
            float _BlurLevel;
            float _CloudStrength;
            float _CloudDither;
            int _FadeType;

            sampler2D _CloudNoiseTexture; float4 _CloudNoiseTexture_TexelSize;

            struct appdata
            {
                UNITY_VERTEX_INPUT_INSTANCE_ID 
                float4 vertex : POSITION;
            };

            struct v2f
            {
                UNITY_VERTEX_INPUT_INSTANCE_ID 
                float4 pos : SV_POSITION;
                float4 depthTextureUv : TEXCOORD1;
                float4 rayFromCamera : TEXCOORD2;
                SHADOW_COORDS(3)
                UNITY_VERTEX_OUTPUT_STEREO
            };

            UNITY_DECLARE_DEPTH_TEXTURE(_CameraDepthTexture);

            // Dj Lukis.LT's oblique view frustum correction (VRChat mirrors use such view frustum)
            // https://github.com/lukis101/VRCUnityStuffs/blob/master/Shaders/DJL/Overlays/WorldPosOblique.shader
            inline float4 CalculateObliqueFrustumCorrection()
            {
                float x1 = -UNITY_MATRIX_P._31 / (UNITY_MATRIX_P._11 * UNITY_MATRIX_P._34);
                float x2 = -UNITY_MATRIX_P._32 / (UNITY_MATRIX_P._22 * UNITY_MATRIX_P._34);
                return float4(x1, x2, 0, UNITY_MATRIX_P._33 / UNITY_MATRIX_P._34 + x1 * UNITY_MATRIX_P._13 + x2 * UNITY_MATRIX_P._23);
            }
            inline float CorrectedLinearEyeDepth(float z, float correctionFactor)
            {
                return 1.f / (z / UNITY_MATRIX_P._34 + correctionFactor);
            }

            bool SceneZDefaultValue()
            {
                #if UNITY_REVERSED_Z
                    return 0.f;
                #else
                    return 1.f;
                #endif
            }

            v2f vert(appdata v)
            {
                float4 worldPosition = mul(unity_ObjectToWorld, v.vertex);
                const fixed3 baseWorldPos = unity_ObjectToWorld._m03_m13_m23;
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.pos = mul(UNITY_MATRIX_VP, worldPosition);
                o.depthTextureUv = ComputeGrabScreenPos(o.pos);
                // Warp ray by the base world position, so it's possible to have reoriented fog
                o.rayFromCamera.xyz = worldPosition.xyz - _WorldSpaceCameraPos.xyz;
                o.rayFromCamera.w = dot(o.pos, CalculateObliqueFrustumCorrection()); // oblique frustrum correction factor
                //o.vertex2 = float4(UnityObjectToViewPos(v.pos), 1.0);
                TRANSFER_SHADOW(o);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                return o;
            }

            #if _CLOUDS
            float remap_pdf_tri_unity( float v )
            {
                v = v*2.0-1.0;
                return sign(v) * (1.0 - sqrt(1.0 - abs(v)));
            }
            float r2dither(float2 pixel) {
                const float a1 = 0.75487766624669276;
                const float a2 = 0.569840290998;
                return frac(a1 * float(pixel.x) + a2 * float(pixel.y));
            }
            float snoise(float3 x) 
            {
                float f = frac(x.z);
                float i = floor(x.z); 
                f *= f * (3. - 2.*f);
                float2 uv = x.xy*float2(0.00390625, -0.00390625) + float2(37, 17)*i*float2(0.00390625, -0.00390625) + 0.001953125;
                float2 n = tex2Dlod(_CloudNoiseTexture, float4(uv, 0, 0)).yx;
                return lerp(n.x, n.y, f);
            }
            const float4x4 m = 
            float4x4( 0.00,  0.80,  0.60, -0.4,
                     -0.80,  0.36, -0.48, -0.5,
                     -0.60, -0.48,  0.64,  0.2,
                      0.40,  0.30,  0.20,  0.4);
            #endif 

            float fogFactorExp2( float dist, float density) 
            {
              const float LOG2 = -1.442695;
              float d = density * dist;
              return 1.0 - clamp(exp2(d * d * LOG2), 0.0, 1.0);
            }

            // Calculates the sun shape
            half calcSunAttenuation(half3 lightPos, half3 ray)
            {
                half3 delta = lightPos - ray;
                half dist = length(delta);
                half sunSize =  _SunSize; 
                half spot = 1.0 - smoothstep(0.0, sunSize, dist);
                return spot * spot;
            }

            // https://iquilezles.org/www/articles/fog/fog.htm
            float fogFactorNonConstant(float3 rayOri, float3 rayDir, float distance, float c, float b)
            {
                return c * exp(-rayOri.y*b) * (1.0-exp( -distance*rayDir.y*b ))/rayDir.y;
            }

            float fogFactorNonConstantAlt(float3 rayOri, float3 rayDir, float distance, float c, float b)
            {
                rayDir.y = abs(rayDir.y);
                return c * exp(-rayOri.y*b) * (1.0-exp( -distance*rayDir.y*b ))/rayDir.y;
            }

            float4 frag(v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(ps);
                float perspectiveDivide = 1.f / i.pos.w;
                float4 rayFromCamera = i.rayFromCamera * perspectiveDivide;
                float2 depthTextureUv = i.depthTextureUv.xy * perspectiveDivide;
                const fixed3 baseWorldPos = unity_ObjectToWorld._m03_m13_m23;

                float sceneZ = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, depthTextureUv);
                bool isSkybox = (sceneZ == SceneZDefaultValue());
                if (isSkybox)
                {
                    // This is skybox, depth texture has default value
                    // It's scene dependant on whether we want the fog to be clipped by the skybox
                    clip(-_ApplySkybox);
                    sceneZ = 0;
                }

                // linearize depth and use it to calculate background world position
                float sceneDepth = CorrectedLinearEyeDepth(sceneZ, rayFromCamera.w*perspectiveDivide);
                float3 worldPosition = rayFromCamera.xyz * sceneDepth + _WorldSpaceCameraPos.xyz;
                float4 localPosition = mul(unity_WorldToObject, float4(worldPosition, 1));
                float localDepth = CorrectedLinearEyeDepth(i.pos.z, rayFromCamera.w);

                float clipAt = (localDepth < sceneDepth);

                localPosition.xyz /= localPosition.w;

                float4 color = UNITY_SAMPLE_TEXCUBE_LOD( unity_SpecCube0, rayFromCamera, _BlurLevel);
                color = _Color * float4(DecodeHDR(color, unity_SpecCube0_HDR), 1.0);

                // Add sun, but ONLY to farthest depth
                if (sceneZ == 0) //SceneZDefaultValue() is replaced by 0
                {
                    float sunAtt = calcSunAttenuation(_WorldSpaceLightPos0.xyz, rayFromCamera);
                    //color.rgb = color.rgb * (1-sunAtt) + sunAtt * _LightColor0.xyz;
                    color.rgb += sunAtt * _LightColor0.xyz;
                }

                //float horiFade = pow(1-abs(rayFromCamera.y), 1/(0.2*_FogStrengthB));
                //float fogFade = fogFactorExp2(_FogStrengthB * 0.02, sceneDepth);

                #if _CLOUDS
                // Don't attempt to get noise if we're in the skybox.
                if (!isSkybox)
                {
                    // ref: https://www.shadertoy.com/view/tsjyzV
                    // Dither input to noise function to compensate for texture sampling imprecision.
                    // But not with a texture. ALU is cheaper, right? 
                    // 8 bit fixed point so adjust sub pixel precision by 1/256
                    float ditherSize = (1.0/256.0) * 0.1;
                    float d1 = remap_pdf_tri_unity(r2dither(i.pos.xy + .99));
                    float d2 = remap_pdf_tri_unity(r2dither(i.pos.xy + .33));
                    float d3 = remap_pdf_tri_unity(r2dither(i.pos.xy + .66));

                    float3 dither = float3(d1, d2, d3) * _CloudDither;

                    float f;

                    float3 q = worldPosition * _CloudDirection.xyz * _CloudDirection.w;
                    q += _Time.x * _CloudMovement.xyz * _CloudMovement.w;

                    q += _CloudNoiseTexture_TexelSize.zwz * dither * ditherSize;

                    f  = 0.5000*snoise( q ); q = mul(m,q)*2.01;
                    f += 0.2500*snoise( q ); q = mul(m,q)*2.02;
                    f += 0.1250*snoise( q ); q = mul(m,q)*2.03;
                    f += 0.0625*snoise( q ); q = mul(m,q)*2.01;

                    f = f * 2 - 1;

                    f *= _CloudStrength;

                    _FogStrengthB *= 1+f;
                }
                #endif

                // a is the density at y = 0
                // b is the density
                // c is a/b
                float fogAmount = fogFactorNonConstant(_WorldSpaceCameraPos, rayFromCamera, sceneDepth, 
                    _FogStrengthA/_FogStrengthB, _FogStrengthB);

                color.a *= fogAmount;
                color.a = saturate(color.a);

                if (_ApplyClip) color.a *= clipAt;

                #if !_PREMULTIPLY
                color.rgb *= color.a;
                #endif

                return color;
            }

            ENDCG
        }
    }
    }