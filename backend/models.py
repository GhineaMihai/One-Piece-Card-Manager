from sqlalchemy import Column, Integer, String, ForeignKey, Table
from sqlalchemy.orm import relationship, Mapped, mapped_column
from sqlalchemy.dialects.postgresql import ARRAY
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    first_name = Column(String, nullable=False)
    last_name = Column(String, nullable=False)
    email = Column(String, unique=True, nullable=False)
    username = Column(String, unique=True, nullable=False)
    password = Column(String, nullable=False)

    collection = relationship("Collection", back_populates="user", uselist=False)


class Collection(Base):
    __tablename__ = "collections"

    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True)

    user = relationship("User", back_populates="collection")
    cards = relationship("CollectionCard", back_populates="collection")


class Card(Base):
    __tablename__ = "cards"

    id = Column(Integer, primary_key=True)
    card_id = Column(String, unique=True, nullable=False)  # External card identifier
    name = Column(String, nullable=False)
    image = Column(String, nullable=False)
    color = Column(ARRAY(String))  # List of colors
    type = Column(String, nullable=False)
    cost = Column(Integer)

    collections = relationship("CollectionCard", back_populates="card")


class CollectionCard(Base):
    __tablename__ = "collection_cards"

    id = Column(Integer, primary_key=True)
    collection_id = Column(Integer, ForeignKey("collections.id"))
    card_id = Column(Integer, ForeignKey("cards.id"))
    count = Column(Integer, default=1)

    collection = relationship("Collection", back_populates="cards")
    card = relationship("Card", back_populates="collections")


class DeckList(Base):
    __tablename__ = "decklists"

    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    user_id = Column(Integer, ForeignKey("users.id"))

    user = relationship("User")
    cards = relationship("DeckCard", back_populates="deck")


class DeckCard(Base):
    __tablename__ = "deck_cards"

    id = Column(Integer, primary_key=True)
    deck_id = Column(Integer, ForeignKey("decklists.id"))
    card_id = Column(Integer, ForeignKey("cards.id"))
    count = Column(Integer, default=1)

    deck = relationship("DeckList", back_populates="cards")
    card = relationship("Card")
