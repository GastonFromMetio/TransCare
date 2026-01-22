# TransCare

TransCare est une application mobile de transcription vocale medicale. Elle permet de dicter une prescription, d'obtenir une transcription locale (offline) et d'envoyer les donnees a l'API pour traitement et suivi.

## Contexte

- Objectif: simplifier la saisie de prescriptions par dictée vocale et fiabiliser les informations medicales.
- Cible: prescripteurs (mobile) et prestataires (backend/validation).
- Fonctionnement principal: transcription locale avec Whisper, puis interaction avec l'API pour authentification et flux prescriptions.

## Fonctionnement de l'app

1) Authentification
   - Inscription, connexion, recuperation du profil, deconnexion.
   - Token Bearer stocke localement.
2) Dictée vocale
   - Enregistrement audio en WAV 16 kHz mono.
   - Transcription locale avec Whisper (offline).
3) Flux prescriptions
   - Envoi de la transcription a l'API.
   - Recuperation des details, correction, validation et suivi de statut.

## API (resume)

Base URL: `/api`

Public:
- `POST /auth/register`
- `POST /auth/login`
- `GET /health`

Protege (Bearer):
- `POST /auth/logout`
- `GET /auth/user`
- `GET /prescriptions`
- `POST /prescriptions`
- `GET /prescriptions/{id}`
- `GET /prescriptions/{id}/poll`
- `PATCH /prescriptions/{id}`
- `POST /prescriptions/{id}/validate`
- `POST /prescriptions/status`
- `GET /prescriptions/pool`
- `GET /prescriptions/pending-approval`
- `POST /prescriptions/{id}/claim`
- `POST /prescriptions/{id}/approve`
- `POST /prescriptions/{id}/dispense`

## Mise en route (smartphone)

### Prerequis

- Flutter installe (`flutter doctor` OK)
- Un appareil Android ou iOS en mode developpeur
- Permissions micro actives

### Android (appareil physique)

1) Activer le mode developpeur et le debogage USB.
2) Connecter le telephone en USB.
3) Verifier l'appareil:
   ```bash
   flutter devices
   ```
4) Lancer l'app:
   ```bash
   flutter run
   ```

### iOS (appareil physique)

1) Activer le mode developpeur sur l'iPhone.
2) Ouvrir `ios/Runner.xcworkspace` dans Xcode.
3) Selectionner l'iPhone comme cible et lancer.

### Configuration API

Par defaut, l'app utilise:

```
API_BASE_URL=http://transcare.713.fr
```

Pour pointer vers un autre serveur:

```bash
flutter run --dart-define=API_BASE_URL=http://votre-serveur
```

## Notes techniques

- Transcription offline via Whisper (ex: `whisper_flutter_new`).
- Enregistrement WAV 16 kHz mono requis pour de bonnes performances.
- Permissions:
  - Android: `RECORD_AUDIO` dans `AndroidManifest.xml`
  - iOS: `NSMicrophoneUsageDescription` dans `Info.plist`
