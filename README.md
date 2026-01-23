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
7) Generation du PDF et affichage sur une page dediee.
8) Si la signature existe deja, bouton "Valider" (appel `POST /prescriptions/{id}/validate` sans JSON).
9) Si pas de signature, affichage de la page de signature avant le PDF, puis appel `POST /prescriptions/{id}/validate`.

## Backend (Laravel 12) - Documentation technique

API REST pour application Flutter, avec authentification par token, Docker et deploiement automatise.

### Objectifs d'integration (Mobile <-> Backend <-> LLM)

- (M) Envoyer la transcription au backend et recevoir l'accuse de reception.
- (B) Utiliser le texte et un schema JSON pour requeter un LLM et produire un JSON structure.
- (M) Polling pour recuperer l'ordonnance (JSON) ou "en attente".
- (B) Stocker le JSON LLM jusqu'a demande du mobile.
- (B) Retourner le JSON au mobile lors du polling.
- (M) Presenter l'ordonnance, accepter validation ou correction utilisateur.
- (M) Envoyer les modifications au backend.
- (B) Appliquer les modifications et stocker l'ordonnance en base.
- (B) Exposer la liste des ordonnances aux utilisateurs backend.
- (B) Mettre a jour le statut apres approbation backend.
- (M) Demander regulierement l'etat des ordonnances en attente.
- (M) Passer les ordonnances approuvees a l'historique.

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
- `POST /auth/register/mobile` (prescripteur)
- `POST /auth/register/web` (prestataire)
- `POST /auth/login`
- `GET /health`

Protege (Bearer):
- `POST /auth/logout`
- `GET /auth/user`
- `POST /auth/signature`
- `GET /auth/signature`
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
