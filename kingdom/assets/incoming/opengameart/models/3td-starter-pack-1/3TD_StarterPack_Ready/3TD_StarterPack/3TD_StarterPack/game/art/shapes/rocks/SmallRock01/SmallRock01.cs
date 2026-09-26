
singleton TSShapeConstructor(SmallRock01DAE)
{
   baseShape = "./SmallRock01.DAE";
};

function SmallRock01DAE::onLoad(%this)
{
   %this.removeImposter();
}
