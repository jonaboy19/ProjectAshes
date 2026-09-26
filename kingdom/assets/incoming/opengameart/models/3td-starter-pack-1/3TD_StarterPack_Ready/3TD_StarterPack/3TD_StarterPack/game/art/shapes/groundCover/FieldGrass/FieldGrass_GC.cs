
singleton TSShapeConstructor(FieldGrass_GCDAE)
{
   baseShape = "./FieldGrass_GC.DAE";
};

function FieldGrass_GCDAE::onLoad(%this)
{
   %this.removeImposter();
}
