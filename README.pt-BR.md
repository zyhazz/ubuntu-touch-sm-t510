# Ubuntu Touch no Samsung Galaxy Tab A 10.1 (2019) — SM-T510

Port comunitário do **Ubuntu Touch 24.04-2.x** (Halium 11) para o SM-T510
(`gta3xlwifi`, Exynos 7904). Não é oficial, nem da UBports nem da Samsung.

O SM-T510 vem com o Android em **32 bits**, mas o Ubuntu Touch atual só existe
em 64 bits. O port mantém os serviços de hardware originais de 32 bits da
Samsung e acrescenta as bibliotecas de 64 bits do **Galaxy A30 (SM-A305GT)**,
que usa o mesmo processador e exatamente o mesmo driver de GPU.

**Funciona:** interface, toque, GPU, rotação automática, Wi-Fi, alto-falante e
microfone. **Não funciona:** câmera e suspensão (deep sleep); o carregamento
com o tablet desligado é limitado. Detalhes, instalação e build estão no
[README em inglês](README.md), e o histórico técnico de cada problema está em
[docs/porting-notes.md](docs/porting-notes.md).

Os zips de instalação não são publicados aqui porque contêm bibliotecas e
firmware proprietários da Samsung. Os scripts geram o zip a partir do firmware
oficial.
