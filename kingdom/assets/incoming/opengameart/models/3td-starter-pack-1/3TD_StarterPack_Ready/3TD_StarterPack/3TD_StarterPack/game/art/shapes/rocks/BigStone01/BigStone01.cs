
singleton TSShapeConstructor(BigStone01DAE)
{
   baseShape = "./BigStone01.DAE";
};

function BigStone01DAE::onLoad(%this)
{
   %this.addImposter("0", "6", "0", "0", "1024", "1", "0");
}
