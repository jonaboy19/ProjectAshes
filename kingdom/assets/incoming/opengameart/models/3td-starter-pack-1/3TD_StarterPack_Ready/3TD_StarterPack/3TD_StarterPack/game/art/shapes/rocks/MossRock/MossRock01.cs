
singleton TSShapeConstructor(MossRock01DAE)
{
   baseShape = "./MossRock01.DAE";
};

function MossRock01DAE::onLoad(%this)
{
   %this.addImposter("0", "6", "0", "0", "1024", "1", "0");
}
