# TransCare

TransCare est une application mobile de transcription vocale medicale. Elle permet de dicter une ordonnance, d'obtenir une transcription locale (offline) et d'envoyer les donnees a l'API pour normalisation, validation et suivi.

## Contexte

- Objectif: simplifier la saisie d'ordonnances par dictee vocale et fiabiliser les informations medicales.
- Cible: prescripteurs (mobile) et prestataires (backend/validation).
- Fonctionnement principal: transcription locale avec Whisper, puis interaction avec l'API pour authentification et flux d'ordonnances.

## Fonctionnement global de l'app

1) Authentification
   - Inscription, connexion, recuperation du profil, deconnexion.
   - Token Bearer stocke localement.
2) Dictée vocale
   - Enregistrement audio en WAV 16 kHz mono.
   - Transcription locale avec Whisper (offline) a partir du modele embarque.
3) Flux ordonnances
   - Envoi de la transcription a l'API.
   - Recuperation des details, correction, validation et suivi de statut.

## Pipeline de creation d'ordonnances

1) Capture audio -> WAV 16 kHz mono.
2) Transcription locale (Whisper embarque, langue fr).
3) Envoi de la transcription a l'API (`POST /prescriptions`).
4) Polling de traitement (`GET /prescriptions/{id}/poll`) jusqu'au resultat.
5) Affichage des champs patient/medicaments, corrections eventuelles.
6) Sauvegarde des corrections (`PATCH /prescriptions/{id}`).
7) Validation et mise a jour du statut (`POST /prescriptions/{id}/validate`, puis flux de suivi).

## Technos utilisees

- Flutter + Dart (mobile iOS/Android).
- Transcription locale via Whisper (plugin `whisper_flutter_new`, modele embarque dans `assets/models/`).
- Enregistrement audio via `record` (WAV 16 kHz mono).
- Stockage local du token/profil via `shared_preferences`.
- Appels reseau via `HttpClient` (API REST).
- Outils UI: `google_fonts`, `url_launcher`, `path_provider`, `dart_phonetics`.

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
