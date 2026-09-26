
singleton Material(WhiteBirch01Bark)
{
   mapTo = "WhiteBirch01Bark";
   diffuseMap[0] = "birch_final";
   specular[0] = "0.9 0.9 0.9 1";
   specularPower[0] = "10";
   translucentBlendOp = "None";
   normalMap[0] = "Birch_Final2_NRM.png";
   useAnisotropic[0] = "1";
   doubleSided = "1";
};

singleton Material(WhiteBirch01_ColorEffectR177G27B88_material)
{
   mapTo = "ColorEffectR177G27B88-material";
   diffuseColor[0] = "0.694118 0.105882 0.345098 1";
   specularPower[0] = "10";
   translucentBlendOp = "None";
};

singleton Material(WhiteBirch01Leaf)
{
   mapTo = "WhiteBirch01Leaf";
   diffuseMap[0] = "birchleaf01a";
   specular[0] = "0.9 0.9 0.9 1";
   specularPower[0] = "10";
   translucentBlendOp = "None";
   useAnisotropic[0] = "1";
   subSurface[0] = "1";
   subSurfaceColor[0] = "0.788235 0.835294 0.454902 1";
   doubleSided = "1";
   alphaTest = "1";
   alphaRef = "120";
   normalMap[0] = "BirchLeaf01a_NRM.png";
};
