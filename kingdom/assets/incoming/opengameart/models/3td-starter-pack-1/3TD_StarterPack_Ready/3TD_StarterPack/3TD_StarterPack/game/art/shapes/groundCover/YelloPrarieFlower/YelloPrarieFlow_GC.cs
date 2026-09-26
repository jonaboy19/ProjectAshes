
singleton TSShapeConstructor(YelloPrarieFlow_GCDAE)
{
   baseShape = "./YelloPrarieFlow_GC.DAE";
};

function YelloPrarieFlow_GCDAE::onLoad(%this)
{
   %this.removeImposter();
}
