# PR #4 — standardizacija samo za TEST

Repozitorijum: `zivkovukadinovic-creator/lager-majica-test`.

## Izvor provjere i redoslijed primjene

Korisnik je dostavio tijelo TEST funkcije `dodaj_majice_sa_minimumom`, jedinstveni
indeks `majice_jedinstvena_stavka` i primarni indeks `majice_pkey`, uz potvrdu
naziva TEST projekta `lager-majica-test`. To je pregled dostavljenih definicija,
ne direktan pregled baze. Postojeći podaci, svi triggeri, potpuna RPC signatura,
strani ključevi i konkretan project ref nisu nezavisno provjereni.

Postojeći indeks koristi lower(trim(model)), lower(trim(boja)), upper(trim(velicina)).
Ne pokriva dijakritičke/model alias varijante niti XXL/2XL: migracija je potrebna.

1. Potvrditi project ref u TEST dashboardu i vezu HTML-a sa tim projektom.
2. Napraviti backup i ručno izvršiti `sql/TEST-inspect-standardization.sql` samo
   u TEST bazi. Pregledati sve definicije, zavisnosti i podatke.
3. Pregledati `sql/TEST-migrate-standardization.sql`. Tek u potvrđenom TEST
   editoru otkomentarisati SET LOCAL zaštitu. Ta izjava je ručna potvrda, nije
   automatska provjera identiteta projekta. Skript ne pokretati u produkciji.
4. Ručno primijeniti migraciju u TEST bazi prije upotrebe nove verzije aplikacije.
   Ako bilo šta ne uspije, izvršiti ROLLBACK; riješiti uzrok prije ponavljanja.
5. Provjeriti ponašanje aplikacije i baze prije spajanja PR-a.

Codex nije izvršio SQL niti poslao zahtjeve Supabase-u. Skript nije idempotentan:
uspješno primijenjenu migraciju ne ponavljati. Ne mijenja autentifikaciju, uloge,
RLS, postojeće dozvole, logo ili raspored.

## Duplikati i migracija

Migracija u jednoj transakciji zaključava tabelu protiv konkurentnih upisa,
prijavljuje sve kanonske kolizije sa ID-jevima, bojama, količinama i minimumima,
i prekida se ako ih ima. Nema DELETE-a niti automatskog spajanja. Time se izbjegava
nagađanje jesu li količine odvojene zalihe ili dvostruki unos. Za svaki par/grupu
potrebna je zasebna, eksplicitno pregledana odluka o količini i minimumu, kao i
provjera referenci na ID-jeve. Minimum se ne sabira niti bira automatski MAX/MIN.

Ako nema kolizija, mijenjaju se samo poznati nazivi modela i veličina. ID-jevi,
količine i minimalne količine ostaju isti. Nepoznati nazivi modela se čuvaju.
Dodaje se kanonski jedinstveni indeks i BEFORE INSERT/UPDATE trigger koji
normalizuje upise. Postojeći indeks ostaje jer ga RPC koristi za ON CONFLICT.
Kanonski indeks štiti i direktne upise; konfliktni direktni INSERT/UPDATE se
odbija, dok dodavanje količine ide kroz postojeći RPC. Nijedna provjera u
pregledniku nije zamjena za bazni indeks.

RPC tijelo se zamjenjuje uz očuvanje stvarne signature, povratnog tipa, vlasnika,
SECURITY postavki i grantova pomoću pg_get_functiondef/CREATE OR REPLACE.
Skript odbija neočekivane overload-e, jezik ili nazive parametara. Puni SQL treba
pregledati i testirati u TEST bazi prije primjene; lokalni PostgreSQL nije dostupan.

## Količine i minimumi pri redovnom korišćenju

Zadržana je dostavljena poslovna logika: RPC prihvata pozitivnu količinu,
postojećoj količini atomski dodaje unesenu količinu, a minimum postavlja na
unesenu minimalnu količinu. Primjer: stanje 7/minimum 4 + unos 3/minimum 6 daje
stanje 10/minimum 6. Unos minimuma 0 isključuje upozorenje za dopunu.
To je postojeće ponašanje RPC-a; nije politika spajanja starih duplikata.

Uređivanje postojećeg ID-a postavlja apsolutnu količinu i minimum kao ranije.
Uređivanje u zauzet kanonski ključ blokira se, bez sabiranja. Preglednik unaprijed
prijavljuje kolizije, a migrirana baza garantuje jedinstvenost i pri istovremenim
upisima. Aplikacija uvijek šalje standardizovane poznate modele i veličine.

## Ručni testovi prije spajanja

- Na odvojenim TEST podacima provjeriti da migracija sa Muska/Muška i XXL/2XL
  kolizijama prekida rad i ostavlja sve ID-jeve, količine i minimume netaknute.
- Bez kolizija potvrditi promjenu samo naziva, isti broj redova i iste količine/minimume.
- Unositi Muška/Muska/MUŠKA i Dječja/Djecija/Dječija, te XXL/2XL, 6XL/XXXXXXL,
  10XL i veće veličine. Potvrditi isti ID, sabiranje količine i zamjenu minimuma.
- Paralelni RPC unosi moraju oba uvećati isti red bez gubitka količine. Posljednji
  obrađeni unos određuje minimum, kao i ranije. Direktni konfliktni INSERT/UPDATE
  mora biti odbijen pod postojećim korisničkim dozvolama.
- Provjeriti boje sa razlikom u veličini slova, nepoznate modele, uređivanje u
  zauzet ključ, minimum 0, stanje na minimumu i odbijanje RPC količine 0.
- Provjeriti sve filtere zajedno i reset, redoslijed XS/S/M/L/XL/2XL… u lageru,
  dopuni i Excelu. Otvoriti pravi XLSX, provjeriti vrijednosti i broj redova.
- Provjeriti urednika, korisnika bez prava uređivanja, desktop i telefon.

Lokalno: `node --test tests/standardization.test.cjs`; zamjenski podaci bez baze.
