# Guida agli asset — cosa serve da te e come prepararlo

Tutto quello che il codice non può fare da solo: modelli dei personaggi,
suoni veri, musica. Ogni sezione dice **cosa scaricare, dove metterlo, con
che nome**. Il resto (integrazione, test, commit) lo fa Claude nella sessione
dopo: basta dire "ho messo la volpe" / "ho messo i suoni".

Metti i download grezzi in `art/` (ignorata da git); i file finali vanno
nei percorsi indicati sotto.

---

## 1. Personaggi (Meshy → Mixamo)

Stessa pipeline del leopardo. Per ognuno servono **2 download da Meshy** e
**9 download da Mixamo**.

### 1a. Meshy — genera il modello

Text to 3D, stile *Cartoon / Low poly*, simmetria ON, PBR OFF se possibile.
Prompt (copia-incolla):

**Volpe (NPC)**
```
cute cartoon fox character, standing upright on two legs like a mascot, big round head, large friendly eyes, small smile, orange fur with white belly and white tail tip, simple stylized low-poly toon shading, T-pose with arms out, symmetrical, clean flat colours, kids video game character, full body, plain background
```

**Panda (NPC)**
```
cute cartoon panda character, standing upright on two legs like a mascot, chubby round body, big round head, large friendly eyes, sleepy smile, black and white fur, simple stylized low-poly toon shading, T-pose with arms out, symmetrical, clean flat colours, kids video game character, full body, plain background
```

**Slime (nemico)** — non serve Mixamo, non ha gambe:
```
cute cartoon slime enemy, rounded blob shape with a flat bottom, two big round eyes and a small cheeky grin, glossy green jelly, simple stylized low-poly toon shading, symmetrical, clean flat colours, kids video game enemy, plain background
```

Regole che hanno funzionato con il leopardo:
* **T-pose obbligatoria** per volpe e panda (Mixamo rigga solo così).
* Scarica **due volte**: `GLB con texture` (per il gioco) e `FBX senza
  texture` (per Mixamo: quello con texture fa fallire l'auto-rigger).
* Nomi: `art/meshy/fox/fox.glb`, `art/meshy/fox/fox_untextured.fbx`; idem
  `panda/`, `slime/slime.glb`.

### 1b. Mixamo — rig e animazioni (solo volpe e panda)

1. mixamo.com → Upload character → l'**FBX senza texture**.
2. Auto-rigger: metti i marker (mento, polsi, gomiti, ginocchia, inguine),
   scheletro *Standard*, 65 ossa va bene. Se dice "unable to map your
   existing skeleton" hai caricato quello con texture.
3. Scarica il **rig** con l'animazione *Breathing Idle*: formato FBX Binary,
   skin **With Skin**, 30 fps, keyframe reduction none →
   `art/meshy/fox/fox_rig.fbx`.
4. Scarica le clip, stesso formato ma skin **Without Skin**, con questi nomi
   esatti (cerca il nome tra virgolette nella barra di Mixamo):

   | file | clip Mixamo | opzione |
   | --- | --- | --- |
   | `anim_walk.fbx` | "Walking" | In Place OFF (va bene, lo tolgo io) |
   | `anim_run.fbx` | "Running" | idem |
   | `anim_jump.fbx` | "Jump" | — |
   | `anim_fall.fbx` | "Falling Idle" | — |
   | `anim_attack.fbx` | "Kicking" o "Punching" | — |
   | `anim_hurt.fbx` | "Reaction" (hit) | — |
   | `anim_emote.fbx` | "Waving" / "Dancing" | — |

   Per gli NPC bastano walk + emote + hurt; le altre sono opzionali, il
   codice usa quelle che trova.

Cartella finale: `assets/models/meshy/fox/` con `fox.glb`, `fox_rig.fbx`,
`anim_*.fbx`. Claude crea `scenes/characters/visuals/fox_rigged.tscn` e
aggiorna `resources/characters/fox.tres`.

### 1c. Slime

Solo `assets/models/meshy/slime/slime.glb`. Niente rig: lo slime si anima
per codice (squash & stretch), come adesso.

---

## 2. Effetti sonori (ElevenLabs Sound Effects)

elevenlabs.io → *Sound Effects*. Durata come indicata, "prompt influence"
alto. Scarica **MP3 o WAV**, rinomina esattamente così e metti in
`assets/audio/sfx/`. Un file con quel nome sostituisce automaticamente il
suono sintetico: zero codice.

| file | durata | prompt |
| --- | --- | --- |
| `jump.mp3` | 0.4 s | cartoon video game jump, short bouncy "boing" whoosh, playful, clean |
| `double_jump.mp3` | 0.4 s | cartoon double jump, higher pitched bouncy pop with a little sparkle |
| `land.mp3` | 0.3 s | soft cartoon landing thud on grass, light and bouncy |
| `attack.mp3` | 0.4 s | quick cartoon swipe whoosh, playful paw swing, no impact |
| `hit.mp3` | 0.4 s | cartoon bonk hit on a squishy jelly enemy, comic, satisfying |
| `hurt.mp3` | 0.5 s | cute cartoon animal "ouch" yelp, short, not scary, kids game |
| `enemy_die.mp3` | 0.7 s | cartoon slime popping and splatting, wet comic squish, cheerful |
| `star.mp3` | 0.8 s | bright magical star pickup chime, sparkly ascending twinkle, video game collectible |
| `checkpoint.mp3` | 0.8 s | friendly checkpoint flag activation jingle, three rising notes, video game |
| `unlock.mp3` | 1.5 s | joyful "new ability unlocked" fanfare, short magical jingle, kids game |
| `fanfare.mp3` | 2.5 s | cheerful level complete victory fanfare, cartoon brass and bells, celebratory, short |
| `portal.mp3` | 1.2 s | magical portal whoosh, shimmering teleport, rising sparkle, cartoon |
| `turbo.mp3` | 1.0 s | cartoon kart turbo boost, rocket whoosh with a playful engine rev |
| `ui.mp3` | 0.2 s | soft UI click, cartoon menu blip, clean |
| `engine.wav` | 2 s, **loop** | small cartoon go-kart engine idle hum, steady, loopable, no variation |

Per `engine.wav` chiedi esplicitamente "seamless loop": il gioco lo ripete e
ne alza il pitch con la velocità. Se il loop "salta" prova con Audacity:
Effetti → Crossfade loop, oppure tagliane un pezzo centrale.

---

## 3. Musica (Suno)

Due tracce, formato MP3, in `assets/audio/music/`. Il gioco le ripete in
loop e le cambia da solo isola ↔ livello. Senza file: silenzio, nessun
errore.

**`hub.mp3` — isola** (2–3 min, chiedi "loopable, no fade out")
```
happy cheerful kids adventure game island theme, ukulele, marimba, light hand percussion, whistling melody, sunny beach vibe, playful and relaxed, instrumental, video game soundtrack, loopable
```

**`level.mp3` — livelli** (2–3 min, "loopable")
```
upbeat playful platformer level music, bouncy synth and xylophone melody, driving drums, adventurous and fun, cartoon video game soundtrack, energetic but not aggressive, instrumental, loopable
```

Opzionali per dopo: `boss.mp3`, `title.mp3`.

---

## 4. Checklist consegna

- [ ] `assets/models/meshy/fox/` — fox.glb, fox_rig.fbx, anim_walk/emote/hurt(.fbx)
- [ ] `assets/models/meshy/panda/` — idem
- [ ] `assets/models/meshy/slime/slime.glb`
- [ ] `assets/audio/sfx/*.mp3` (i nomi della tabella)
- [ ] `assets/audio/music/hub.mp3`, `level.mp3`

Poi: "riprendi, ho messo X". Claude integra, testa (suite headless +
screenshot) e committa.
