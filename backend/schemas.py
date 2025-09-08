from pydantic import BaseModel
from datetime import datetime
from typing import List, Optional


# ========== CARD ==========
class CardBase(BaseModel):
    card_id: str
    name: str
    image: str
    color: List[str]
    type: str
    cost: int

class CardCreate(CardBase):
    pass

class CardRead(CardBase):
    id: int
    name: str
    card_id: str

    class Config:
        orm_mode = True

class CardAutocomplete(BaseModel):
    id: int
    name: str
    card_id: str

    class Config:
        orm_mode = True

# ========== COLLECTION CARD ==========
class CollectionCardBase(BaseModel):
    card_id: int
    count: int

class CollectionCardCreate(BaseModel):
    card_id: int
    count: int = 1

class CollectionCardRead(BaseModel):
    id: int
    count: int
    card: CardRead

    class Config:
        orm_mode = True


# ========== COLLECTION ==========
class CollectionRead(BaseModel):
    id: int
    cards: List[CollectionCardRead]

    class Config:
        orm_mode = True


# ========== USER ==========
class UserBase(BaseModel):
    first_name: str
    last_name: str
    email: str
    username: str

class UserCreate(UserBase):
    password: str

class UserRead(UserBase):
    id: int
    collection: Optional[CollectionRead] = None

    class Config:
        orm_mode = True

class UserLogin(BaseModel):
    username: str
    password: str


class DeckCardBase(BaseModel):
    card_id: int
    count: int

class DeckCardCreate(DeckCardBase):
    pass

class DeckCardRead(BaseModel):
    id: int
    card: CardRead
    count: int

    class Config:
        orm_mode = True


class DeckListCreate(BaseModel):
    name: str
    cards: List[DeckCardCreate]


class DeckListRead(BaseModel):
    id: int
    name: str
    cards: List[DeckCardRead]

    class Config:
        orm_mode = True
