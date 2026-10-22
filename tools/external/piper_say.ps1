# NPC voice line with Piper TTS (old MIT binary 2023.11.14-2, CPU, ~6 s per short line).
#   powershell -File tools/external/piper_say.ps1 -Voice norman -Text "Forty people slept that night." -Out line.wav
# Voices (licence-cleared, see tools/README_EXTERNAL_TOOLS.md): norman (male, public domain), john (male, public domain),
#   kristin (female, public domain), cori (UK female, public domain, high quality), young (libritts-high speaker 250, higher voice, CC-BY 4.0: credit "LibriTTS, Zen et al. 2019" + Piper),
#   deep (libritts-high speaker 400, low voice, CC-BY 4.0, same credit).
param([Parameter(Mandatory)][string]$Voice, [Parameter(Mandatory)][string]$Text, [Parameter(Mandatory)][string]$Out, [double]$LengthScale = 1.0)
$root = "C:\Users\Jonna\Tools\piper"
$map = @{
  norman  = @("en_US-norman-medium", $null); john = @("en_US-john-medium", $null); kristin = @("en_US-kristin-medium", $null)
  cori    = @("en_GB-cori-high", $null); young = @("en_US-libritts-high", 250); deep = @("en_US-libritts-high", 400)
}
if (-not $map.ContainsKey($Voice)) { throw "unknown voice '$Voice'; use: $($map.Keys -join ', ')" }
$m, $spk = $map[$Voice]
$a = @("-m", "$root\voices\$m.onnx", "-f", $Out, "--length_scale", $LengthScale)
if ($null -ne $spk) { $a += @("--speaker", $spk) }
$Text | & "$root\piper\piper.exe" @a 2>&1 | Select-Object -Last 1
