extends RefCounted

## Small original PCM cues, authored locally and sent through the host's SFX bus.

const SAMPLE_RATE := 22050
const CUES := {
	"move": Vector3(0.13, 430.0, 1.0),
	"capture": Vector3(0.22, 295.0, 1.6),
	"crown": Vector3(0.42, 740.0, 0.4),
	"finish": Vector3(0.62, 554.0, 0.25),
}


## A match reuses four short buffers instead of synthesizing during a jump.
static func make_cues() -> Dictionary[String, AudioStreamWAV]:
	var sounds: Dictionary[String, AudioStreamWAV] = {}
	for cue: String in CUES:
		var spec: Vector3 = CUES[cue]
		var count := ceili(spec.x * SAMPLE_RATE)
		var pcm := PackedByteArray()
		pcm.resize(count * 2)
		for index in count:
			var t := float(index) / SAMPLE_RATE
			var envelope := minf(t / 0.003, 1.0) * exp(-t * 8.0 / spec.x)
			var tail := clampf((spec.x - t) / 0.018, 0.0, 1.0)
			var tone := sin(TAU * spec.y * t)
			tone += sin(TAU * spec.y * 2.71 * t) * 0.3 * exp(-t * 45.0)
			var knock := sin(TAU * 1379.0 * t) * sin(TAU * 791.0 * t)
			var sample := (tone * 0.45 + knock * spec.z * exp(-t * 90.0) * 0.2)
			if cue == "crown" or cue == "finish":
				sample += sin(TAU * spec.y * 1.5 * t) * 0.16
			pcm.encode_s16(index * 2, roundi(
				clampf(sample * envelope * tail, -0.95, 0.95) * 32767.0
			))
		var sound := AudioStreamWAV.new()
		sound.format = AudioStreamWAV.FORMAT_16_BITS
		sound.mix_rate = SAMPLE_RATE
		sound.stereo = false
		sound.data = pcm
		sounds[cue] = sound
	return sounds
