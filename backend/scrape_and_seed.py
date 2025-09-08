import requests
from bs4 import BeautifulSoup
from database import SessionLocal, engine
from models import Base, Card
from PIL import Image
import io
import os
import re
from urllib.parse import urlparse, parse_qs

# Create folder if needed
os.makedirs("cards", exist_ok=True)

# Initialize DB
Base.metadata.create_all(bind=engine)
db = SessionLocal()

# All One Piece card set URLs
SET_URLS = [
    "https://onepiece.limitlesstcg.com/cards/op01-romance-dawn",
    "https://onepiece.limitlesstcg.com/cards/op02-paramount-war",
    "https://onepiece.limitlesstcg.com/cards/op03-pillars-of-strength",
    "https://onepiece.limitlesstcg.com/cards/op04-kingdoms-of-intrigue",
    "https://onepiece.limitlesstcg.com/cards/op05-awakening-of-the-new-era",
    "https://onepiece.limitlesstcg.com/cards/op06-wings-of-the-captain",
    "https://onepiece.limitlesstcg.com/cards/eb01-memorial-collection",
    "https://onepiece.limitlesstcg.com/cards/op07-500-years-in-the-future",
    "https://onepiece.limitlesstcg.com/cards/op08-two-legends",
    "https://onepiece.limitlesstcg.com/cards/prb01-premium-booster-one-piece-the-best",
    "https://onepiece.limitlesstcg.com/cards/op09-emperors-in-the-new-world",
    "https://onepiece.limitlesstcg.com/cards/op10-royal-blood",
    "https://onepiece.limitlesstcg.com/cards/eb02-anime-25th-collection",
    "https://onepiece.limitlesstcg.com/cards/op11-a-fist-of-divine-speed",
    "https://onepiece.limitlesstcg.com/cards/st01-straw-hat-crew",
    "https://onepiece.limitlesstcg.com/cards/st02-worst-generation",
    "https://onepiece.limitlesstcg.com/cards/st03-the-seven-warlords-of-the-sea",
    "https://onepiece.limitlesstcg.com/cards/st04-animal-kingdom-pirates",
    "https://onepiece.limitlesstcg.com/cards/st05-one-piece-film-edition",
    "https://onepiece.limitlesstcg.com/cards/st06-absolute-justice",
    "https://onepiece.limitlesstcg.com/cards/st07-big-mom-pirates",
    "https://onepiece.limitlesstcg.com/cards/st08-monkey-d-luffy",
    "https://onepiece.limitlesstcg.com/cards/st09-yamato",
    "https://onepiece.limitlesstcg.com/cards/st10-the-three-captains",
    "https://onepiece.limitlesstcg.com/cards/st11-uta",
    "https://onepiece.limitlesstcg.com/cards/st12-zoro-sanji",
    "https://onepiece.limitlesstcg.com/cards/st13-the-three-brothers",
    "https://onepiece.limitlesstcg.com/cards/st14-3D2Y",
    "https://onepiece.limitlesstcg.com/cards/st15-red-edward-newgate",
    "https://onepiece.limitlesstcg.com/cards/st16-green-uta",
    "https://onepiece.limitlesstcg.com/cards/st17-blue-donquixote-doflamingo",
    "https://onepiece.limitlesstcg.com/cards/st18-purple-monkey-d-luffy",
    "https://onepiece.limitlesstcg.com/cards/st19-black-smoker",
    "https://onepiece.limitlesstcg.com/cards/st20-yellow-charlotte-katakuri",
    "https://onepiece.limitlesstcg.com/cards/st21-ex-gear-5",
    "https://onepiece.limitlesstcg.com/cards/st23-red-shanks",
    "https://onepiece.limitlesstcg.com/cards/st24-green-jewelry-bonney",
    "https://onepiece.limitlesstcg.com/cards/st25-blue-buggy",
    "https://onepiece.limitlesstcg.com/cards/st26-purple-black-monkey-d-luffy",
    "https://onepiece.limitlesstcg.com/cards/st27-black-marshall-d-teach",
    "https://onepiece.limitlesstcg.com/cards/st28-green-yellow-yamato"
]

total_added = 0
total_skipped = 0
total_errors = 0

for SET_URL in SET_URLS:
    print(f"\n🌐 Scraping set: {SET_URL}")
    resp = requests.get(SET_URL)
    soup = BeautifulSoup(resp.content, "html.parser")

    links = soup.select("a[href^='/cards/']")
    card_urls = {link['href'] for link in links}

    for relative in sorted(card_urls):
        url = "https://onepiece.limitlesstcg.com" + relative
        try:
            query = parse_qs(urlparse(relative).query)
            version = query.get("v", [None])[0]

            r = requests.get(url)
            s = BeautifulSoup(r.content, "html.parser")

            name_tag = s.select_one("span.card-text-name a")
            id_tag = s.select_one("span.card-text-id")
            type_tag = s.select_one("span[data-tooltip='Category']")
            color_tag = s.select_one('span[data-tooltip="Color"]')

            if not name_tag or not id_tag:
                print(f"⚠️  Skipping {relative} — missing card ID or name")
                total_skipped += 1
                continue

            name = name_tag.text.strip()
            card_id = id_tag.text.strip()
            if version:
                card_id += f"_p{version}"

            # Check if card_id already exists
            if db.query(Card).filter(Card.card_id == card_id).first():
                print(f"⏭️  {card_id} already exists. Skipping.")
                total_skipped += 1
                continue

            card_type = type_tag.text.strip() if type_tag else ""
            colors = [c.strip() for c in color_tag.text.split("/") if c] if color_tag else []

            cost = 0
            if card_type != "Leader":
                type_section = s.select_one("p.card-text-type")
                if type_section:
                    full_text = type_section.get_text(separator=" ").strip()
                    match = re.search(r"(\d+)\s+Cost", full_text)
                    if match:
                        cost = int(match.group(1))

            # Save image
            img_tag = s.select_one("div.card-image img")
            if img_tag and "src" in img_tag.attrs:
                img_url = img_tag["src"]
                try:
                    img_response = requests.get(img_url)
                    img = Image.open(io.BytesIO(img_response.content)).convert("RGBA")
                    image_path = f"cards/{card_id}.png"
                    img.save(image_path, "PNG")
                except Exception as e:
                    print(f"❌ Failed to save image for {card_id}: {e}")
                    total_errors += 1
                    continue
            else:
                print(f"❌ No image found for {card_id}")
                total_errors += 1
                continue

            card = Card(
                card_id=card_id,
                name=name,
                image=image_path,
                color=colors,
                type=card_type,
                cost=cost
            )
            db.add(card)
            db.commit()
            print(f"✅ Added {card_id}: {name}")
            total_added += 1

        except Exception as ex:
            print(f"🔥 Unexpected error on {relative}: {ex}")
            total_errors += 1
            continue

db.close()

print("\n🎯 Scraping finished!")
print(f"✅ Added: {total_added}")
print(f"⏭️ Skipped: {total_skipped}")
print(f"❌ Errors: {total_errors}")
