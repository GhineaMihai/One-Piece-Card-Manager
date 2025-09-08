from sqlalchemy.orm import Session
from sqlalchemy import or_, and_
import models, schemas
import bcrypt

def create_user(db: Session, user: schemas.UserCreate):
    hashed_pw = bcrypt.hashpw(user.password.encode("utf-8"), bcrypt.gensalt())
    db_user = models.User(
        first_name=user.first_name,
        last_name=user.last_name,
        email=user.email,
        username=user.username,
        password=hashed_pw.decode("utf-8")
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)

    # ✅ Create collection for new user
    collection = models.Collection(user_id=db_user.id)
    db.add(collection)
    db.commit()
    db.refresh(db_user)

    return db_user

def create_card(db: Session, card: schemas.CardCreate):
    db_card = models.Card(**card.dict())
    db.add(db_card)
    db.commit()
    db.refresh(db_card)
    return db_card

def get_cards(db: Session):
    return db.query(models.Card).all()

def authenticate_user(db: Session, username: str, password: str):
    user = db.query(models.User).filter(models.User.username == username).first()
    if not user:
        return None
    if not bcrypt.checkpw(password.encode("utf-8"), user.password.encode("utf-8")):
        return None
    return user

def autocomplete_cards(db: Session, q: str, limit: int = 10):
    tokens = q.lower().split()

    # Create conditions for each token to match name OR card_id
    filters = [or_(
        models.Card.name.ilike(f"%{token}%"),
        models.Card.card_id.ilike(f"%{token}%")
    ) for token in tokens]

    return db.query(models.Card).filter(and_(*filters)).limit(limit).all()

def search_cards(
    db: Session,
    card_id: str = None,
    name: str = None,
    type_: str = None,
    cost: int = None,
    color: str = None
):
    query = db.query(models.Card)

    if card_id:
        query = query.filter(models.Card.card_id.ilike(f"%{card_id}%"))
    if name:
        query = query.filter(models.Card.name.ilike(f"%{name}%"))
    if type_:
        query = query.filter(models.Card.type == type_)
    if cost is not None:
        query = query.filter(models.Card.cost == cost)
    if color:
        query = query.filter(models.Card.color.any(color))

    return query.all()

def create_decklist(db: Session, user_id: int, deck_data: schemas.DeckListCreate):
    deck = models.DeckList(name=deck_data.name, user_id=user_id)
    db.add(deck)
    db.commit()
    db.refresh(deck)

    for entry in deck_data.cards:
        deck_card = models.DeckCard(deck_id=deck.id, card_id=entry.card_id, count=entry.count)
        db.add(deck_card)

    db.commit()
    db.refresh(deck)
    return deck


def get_decklists_for_user(db: Session, user_id: int):
    return db.query(models.DeckList).filter_by(user_id=user_id).all()
