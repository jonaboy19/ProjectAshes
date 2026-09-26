
singleton TSShapeConstructor(WhiteBirch01DAE)
{
   baseShape = "./WhiteBirch01.DAE";
};

function WhiteBirch01DAE::onLoad(%this)
{
   %this.addImposter("0", "6", "0", "0", "1024", "1", "0");
}
