
singleton Material(FenceSeg_01_BarbedWire)
{
   mapTo = "BarbedWire";
   diffuseMap[0] = "3td_BarbedWire_02";
   specular[0] = "0.9 0.9 0.9 1";
   specularPower[0] = "10";
   translucentBlendOp = "None";
   useAnisotropic[0] = "1";
   doubleSided = "1";
   alphaTest = "1";
   alphaRef = "50";
};

singleton Material(FenceSeg_01_WoodPost01)
{
   mapTo = "WoodPost01";
   diffuseMap[0] = "3td_woodPost_01_1024";
   specular[0] = "0.9 0.9 0.9 1";
   specularPower[0] = "10";
   translucentBlendOp = "None";
   normalMap[0] = "3td_woodPost_01_1024_NRM.png";
   useAnisotropic[0] = "1";
   doubleSided = "1";
   pixelSpecular[0] = "0";
};

singleton Material(FenceSeg_01_ColorEffectR27G177B27_material)
{
   mapTo = "ColorEffectR27G177B27-material";
   diffuseColor[0] = "0.105882 0.694118 0.105882 1";
   specularPower[0] = "10";
   translucentBlendOp = "None";
};

singleton Material(FenceSeg_02_ColorEffectR176G26B26_material)
{
   mapTo = "ColorEffectR176G26B26-material";
   diffuseColor[0] = "0.690196 0.101961 0.101961 1";
   specularPower[0] = "10";
   translucentBlendOp = "None";
};
