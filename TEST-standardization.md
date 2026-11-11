# PR #4 — status TEST baze

Rad isključivo za `zivkovukadinovic-creator/lager-majica-test`.

## Obavezno prije spajanja

Ovo je nacrt: zaštita na nivou baze još nije implementirana. Repozitorijum ne
sadrži SQL funkcije/ograničenja. Nema podešenog pristupa testnoj bazi niti je
potvrđeno da je Supabase project ref iz HTML-a TEST projekat. Nijedan Supabase
zahtjev nije izvršen; postojeći podaci, RPC i ograničenja nisu pregledani.

`sql/TEST-inspect-standardization.sql` je poseban read-only skript za ručni
pregled isključivo potvrđene TEST baze. Nije migracija i nije izvršen. Rezultate
pregleda funkcija, indeksa, ograničenja, triggera i kandidata za duplikate treba
pregledati prije pisanja migracije. Skriptov pregled kandidata nije zamjena za
provjeru svih stvarnih podataka i Unicode varijanti.

Migracija je potrebna ako baza već nema ekvivalentnu atomsku zaštitu. Tek nakon
pregleda treba pripremiti poseban TEST migracioni SQL koji usklađuje RPC,
kanonske ključeve i jedinstvenost i za INSERT i za UPDATE, bez promjene RLS-a,
uloga, autentifikacije ili postojećih dozvola. SQL se ne izvršava automatski.
Migracija mora prvo prijaviti kolizije i zaustaviti se ako postoje, umjesto da ih
prećutno spoji. Treba provjeriti zavisnosti i strane ključeve.

## Količine i minimumi

Aplikacija ne briše i ne spaja postojeće redove. Prikazuje ih odvojeno, sa
standardizovanim nazivima, i zadržava njihove ID-jeve, količine i minimume.
Više ekvivalentnih redova blokira čuvanje te kombinacije. Uređivanje u ključ
drugog reda takođe je blokirano. Dodavanje na jedan postojeći red šalje njegov
originalni ključ postojećem RPC-u, čime izbjegava razdvajanje stare oznake samo
zbog standardizacije u aplikaciji. Novi ključ se šalje standardizovan.

Ponašanje količine i minimuma pri dodavanju na postojeći red i dalje određuje
postojeći RPC; bez njegove definicije nije moguće tvrditi da li minimum mijenja
ili zadržava. Frontend ne računa novu količinu niti spaja minimume. Za eventualno
ručno spajanje obavezno pregledati svaki ID i količinu, provjeriti da li količine
predstavljaju odvojene zalihe ili dvostruki unos, i eksplicitno dogovoriti jedan
minimum po kombinaciji. Minimum se ne sabira i ne bira se automatski MAX/MIN.

Provjera u pregledniku nije dovoljna za paralelne unose, direktne API klijente,
neučitane redove zbog ograničenja broja rezultata ili redove nevidljive pod RLS-om.
Jedinstvenost mora garantovati testna baza nakon pregleda i migracije.

## Provjera prije spajanja

1. Potvrditi TEST project ref i pregledati rezultat read-only SQL-a.
2. Dovršiti i pregledati zasebnu migraciju; ručno je primijeniti samo u TEST bazi.
3. Unijeti Muška/Muska/MUŠKA i Dječja/Djecija/Dječija sa istom bojom i veličinom;
   potvrditi isti ID i očekivano povećanje količine i ponašanje minimuma.
4. Ponoviti XXL/2XL, XXXL/3XL, 6XL/XXXXXXL i veće veličine, uključujući paralelne
   zahtjeve i direktni RPC/INSERT/UPDATE pod postojećim dozvolama.
5. Provjeriti uređivanje u zauzet ključ, stare duplikate, nepromijenjene količine
   i minimume, minimum 0 i stanje tačno na minimumu.
6. Provjeriti sve filtere zajedno, reset, prirodan redoslijed veličina i Excel
   (standardizovani nazivi, redoslijed, broj redova, količine i formule).
7. Provjeriti urednika i korisnika bez prava uređivanja, desktop i telefon.

Pokretanje lokalnih regresionih provjera: `node --test tests/standardization.test.cjs`.
Testovi koriste izmišljene podatke bez pristupa Supabase-u.
