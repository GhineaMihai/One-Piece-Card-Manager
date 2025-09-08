from typing import List
from fastapi import FastAPI, UploadFile, File, Depends, HTTPException
from fastapi.responses import StreamingResponse
import cv2
from sqlalchemy.orm import Session
import models, schemas, crud
from database import SessionLocal, engine, Base
from PIL import Image
import io
from fastapi.security import OAuth2PasswordBearer
from auth import verify_token
from ultralytics import YOLO
from fastapi.staticfiles import StaticFiles
from fastapi import Body
from fastapi.middleware.cors import CORSMiddleware
from threading import Lock

latest_detections = set()
detections_lock = Lock()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")

# Create DB tables
Base.metadata.create_all(bind=engine)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # or use your device IP / frontend URL for stricter control
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/cards", StaticFiles(directory="cards"), name="cards")

yolo_model = YOLO("model/card_scanner.pt")
last_scan_results = {}  # key: user_id, value: list of card_ids

# Dependency for DB session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


from collections import deque
import threading, time

cap = cv2.VideoCapture("http://192.168.1.130:4747/video/mjpeg")

# Small output size (lower bytes + faster)
OUT_W = 1920
JPEG_QUALITY = 70

# Shared state
_frame_q = deque(maxlen=1)      # holds newest frame only (drop old ones)
_last_annotated = None
_last_detections = set()
_run_detector = True

def _resize_keep_aspect(img, out_w=OUT_W):
    h, w = img.shape[:2]
    out_h = int(h * out_w / w)
    return cv2.resize(img, (out_w, out_h), interpolation=cv2.INTER_AREA)

def _detector_loop():
    global _last_annotated, _last_detections
    while _run_detector:
        if not _frame_q:
            time.sleep(0.005)
            continue

        frame = _frame_q.pop()  # always take newest
        # Run YOLO on the smaller frame
        results = yolo_model.predict(frame, conf=0.6, imgsz=OUT_W, verbose=False)
        annotated = results[0].plot()

        # Update detections
        names = results[0].names
        ids   = results[0].boxes.cls.tolist()
        confs = results[0].boxes.conf.tolist()
        dets = {names[int(i)] for i, c in zip(ids, confs) if c > 0.6}

        with detections_lock:
            latest_detections.clear()
            latest_detections.update(dets)

        _last_detections = dets
        _last_annotated = annotated

# Start detector thread once (e.g., on app startup)
detector_thread = threading.Thread(target=_detector_loop, daemon=True)
detector_thread.start()

@app.get("/video-feed")
def video_feed():
    def gen_frames():
        target_interval = 1.0 / 30.0  # ~30 fps stream
        last_send = 0.0

        while True:
            ok, frame = cap.read()
            if not ok:
                break

            # Your crop
            frame = frame[:frame.shape[0]-185, :frame.shape[1]]

            # Downscale before doing anything
            small = _resize_keep_aspect(frame, OUT_W)

            # Hand the latest frame to detector (non-blocking)
            _frame_q.append(small)

            # Use last annotated if available; otherwise show raw small
            out_img = _last_annotated if _last_annotated is not None else small

            # JPEG encode (lower quality = fewer bytes)
            _, buf = cv2.imencode('.jpg', out_img, [int(cv2.IMWRITE_JPEG_QUALITY), JPEG_QUALITY])
            frame_bytes = buf.tobytes()

            # Stream as MJPEG (keep same format your client expects)
            yield (b'--frame\r\n'
                   b'Content-Type: image/jpeg\r\n\r\n' + frame_bytes + b'\r\n')

            # gentle pacing to avoid huge TCP chunks
            now = time.time()
            sleep = target_interval - (now - last_send)
            if sleep > 0:
                time.sleep(sleep)
            last_send = time.time()

    return StreamingResponse(gen_frames(), media_type="multipart/x-mixed-replace; boundary=frame")


@app.get("/video-scan-results", response_model=list[schemas.CardRead])
def get_video_scan_results(db: Session = Depends(get_db)):
    with detections_lock:
        card_ids = list(latest_detections)

    if not card_ids:
        return []

    cards = db.query(models.Card).filter(models.Card.card_id.in_(card_ids)).all()
    return cards

def get_current_user(token: str = Depends(oauth2_scheme), db: Session = Depends(get_db)):
    payload = verify_token(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid token")

    user_id = int(payload.get("sub"))
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@app.post("/scan", response_model=list[schemas.CardRead])
async def scan_cards(file: UploadFile = File(...), db: Session = Depends(get_db)):
    # Read image
    image = Image.open(io.BytesIO(await file.read())).convert("RGB")

    # Run inference
    results = yolo_model(image)[0]

    # Get names and classes
    class_names = results.names
    class_ids = results.boxes.cls.tolist()
    confidences = results.boxes.conf.tolist()

    # Filter with confidence threshold
    detected_ids = set()
    for cls_idx, conf in zip(class_ids, confidences):
        if conf > 0.6:
            label = class_names[int(cls_idx)]
            detected_ids.add(label)

    if not detected_ids:
        return []

    # Query matching cards from DB
    cards = db.query(models.Card).filter(models.Card.card_id.in_(detected_ids)).all()
    return cards


@app.post("/live-scan", response_model=list[schemas.CardRead])
def live_scan(
    card_ids: List[str],
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    cards = db.query(models.Card).filter(models.Card.card_id.in_(card_ids)).all()
    return cards

@app.get("/last-scan", response_model=list[schemas.CardRead])
def get_last_scan(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    card_ids = last_scan_results.get(current_user.id, [])
    cards = db.query(models.Card).filter(models.Card.card_id.in_(card_ids)).all()
    return cards

@app.get("/collection", response_model=list[schemas.CardRead])
def list_cards(db: Session = Depends(get_db)):
    return crud.get_cards(db)

@app.post("/register", response_model=schemas.UserRead)
def register(user: schemas.UserCreate, db: Session = Depends(get_db)):
    # Prevent duplicate username/email
    if db.query(models.User).filter(models.User.email == user.email).first():
        raise HTTPException(status_code=400, detail="Email already registered")
    if db.query(models.User).filter(models.User.username == user.username).first():
        raise HTTPException(status_code=400, detail="Username already taken")

    return crud.create_user(db, user)

from auth import create_access_token

@app.post("/login")
def login(login_data: schemas.UserLogin, db: Session = Depends(get_db)):
    user = crud.authenticate_user(db, login_data.username, login_data.password)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    token = create_access_token({"sub": str(user.id)})
    return {"access_token": token, "token_type": "bearer"}

@app.post("/users/me/collection", response_model=schemas.CollectionCardRead)
def add_card_to_collection(
    card_data: schemas.CollectionCardCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    collection = current_user.collection
    if not collection:
        raise HTTPException(status_code=404, detail="Collection not found")

    existing_entry = db.query(models.CollectionCard).filter_by(
        collection_id=collection.id,
        card_id=card_data.card_id
    ).first()

    if existing_entry:
        existing_entry.count += card_data.count  # ✅ Adds correct count
        db.commit()
        db.refresh(existing_entry)
        return existing_entry

    new_entry = models.CollectionCard(
        collection_id=collection.id,
        card_id=card_data.card_id,
        count=card_data.count  # ✅ This must use the passed count
    )
    db.add(new_entry)
    db.commit()
    db.refresh(new_entry)
    return new_entry

@app.put("/users/me/collection/{card_id}", response_model=schemas.CollectionCardRead)
def update_card_in_collection(
    card_id: int,
    card_data: schemas.CollectionCardCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    collection = current_user.collection
    if not collection:
        raise HTTPException(status_code=404, detail="Collection not found")

    existing_entry = db.query(models.CollectionCard).filter_by(
        collection_id=collection.id,
        card_id=card_id
    ).first()

    if existing_entry:
        if card_data.count <= 0:
            db.delete(existing_entry)
            db.commit()
            raise HTTPException(status_code=200, detail="Card removed from collection")
        else:
            existing_entry.count = card_data.count
            db.commit()
            db.refresh(existing_entry)
            return existing_entry
    else:
        if card_data.count > 0:
            new_entry = models.CollectionCard(
                collection_id=collection.id,
                card_id=card_id,
                count=card_data.count
            )
            db.add(new_entry)
            db.commit()
            db.refresh(new_entry)
            return new_entry
        else:
            raise HTTPException(status_code=400, detail="Cannot create card with zero or negative count")

@app.get("/card-api/autocomplete", response_model=list[schemas.CardAutocomplete])
def autocomplete_cards_route(q: str, limit: int = 10, db: Session = Depends(get_db)):
    if not q:
        raise HTTPException(status_code=400, detail="Query parameter 'q' is required.")

    tokens = q.lower().split()
    cards = crud.autocomplete_cards(db, q=q, limit=100)


    # Multi-token matching
    filtered = []
    for card in cards:
        combined = f"{card.card_id} {card.name}".lower()
        if all(token in combined for token in tokens):
            filtered.append(card)
            if len(filtered) >= limit:
                break

    return filtered

@app.get("/card-api/search", response_model=list[schemas.CardRead])
def search_cards(
    card_id: str = None,
    name: str = None,
    type: str = None,
    cost: int = None,
    color: str = None,
    db: Session = Depends(get_db)
):
    if not any([card_id, name, type, cost, color]):
        raise HTTPException(status_code=400, detail="At least one filter is required.")

    return crud.search_cards(
        db,
        card_id=card_id,
        name=name,
        type_=type,
        cost=cost,
        color=color
    )

@app.delete("/users/me/collection/{card_id}")
def remove_card_from_collection(
    card_id: int,
    count: int = 1,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    collection = current_user.collection
    if not collection:
        raise HTTPException(status_code=404, detail="Collection not found")

    entry = db.query(models.CollectionCard).filter_by(
        collection_id=collection.id,
        card_id=card_id
    ).first()

    if not entry:
        raise HTTPException(status_code=404, detail="Card not in collection")

    if count >= entry.count:
        db.delete(entry)
    else:
        entry.count -= count

    db.commit()
    return {"detail": "Card removed or count decreased"}

@app.get("/users/me/collection", response_model=schemas.CollectionRead)
def get_own_collection(current_user: models.User = Depends(get_current_user), db: Session = Depends(get_db)):
    if not current_user.collection:
        raise HTTPException(status_code=404, detail="Collection not found")
    return current_user.collection

@app.post("/users/me/decks", response_model=schemas.DeckListRead)
def create_deck(
    deck_data: schemas.DeckListCreate,
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return crud.create_decklist(db, user_id=current_user.id, deck_data=deck_data)


@app.get("/users/me/decks", response_model=List[schemas.DeckListRead])
def get_user_decks(
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return crud.get_decklists_for_user(db, user_id=current_user.id)

@app.delete("/users/me/decks/{deck_id}")
def delete_deck(deck_id: int, db: Session = Depends(get_db), current_user: models.User = Depends(get_current_user)):
    deck = db.query(models.DeckList).filter_by(id=deck_id, user_id=current_user.id).first()
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")

    db.delete(deck)
    db.commit()
    return {"message": "Deck deleted successfully"}

@app.put("/users/me/decks/{deck_id}", response_model=dict)
def update_deck(
    deck_id: int,
    deck_data: schemas.DeckListCreate = Body(...),
    current_user: models.User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    deck = db.query(models.DeckList).filter_by(id=deck_id, user_id=current_user.id).first()
    if not deck:
        raise HTTPException(status_code=404, detail="Deck not found")

    # Update deck name
    deck.name = deck_data.name

    # Clear old cards
    db.query(models.DeckCard).filter(models.DeckCard.deck_id == deck_id).delete()

    # Add new cards
    for card_entry in deck_data.cards:
        new_card = models.DeckCard(
            deck_id=deck_id,
            card_id=card_entry.card_id,
            count=card_entry.count
        )
        db.add(new_card)

    db.commit()
    db.refresh(deck)
    return {"message": "Deck updated successfully"}

@app.get("/api/cards/all", response_model=List[schemas.CardRead])
def get_all_cards(db: Session = Depends(get_db)):
    return db.query(models.Card).all()