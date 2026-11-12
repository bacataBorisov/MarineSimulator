# Reference documents

Immutable primary sources for later M2.6 work. They are not app-bundle resources. The Xcode target synchronizes `NMEASimulator/` only, and these files are outside that folder.

Certified ORC predictions and the historical Farr manufacturer VPP are separate datasets. Do not replace one with the other. Nimana has no manufacturer VPP in this set. Do not infer one from the ORC certificate.

Checksums are SHA-256 of the stored bytes.

## Extasy — ORC Club Certificate

| Field | Value |
| --- | --- |
| Vessel | Extasy, Beneteau First 40.7 |
| Document title | ORC Certificate for Extasy |
| Document type | ORC Club Certificate |
| Certificate number | 010a/26 |
| ORC reference | 03850004W42 |
| Issuer | ORC, issued through ORC Bulgaria, Varna |
| Issue date | 05/08/2026, as printed |
| Validity | Valid until 31/12/2026 |
| VPP version | 2026 1.00 |
| Sail number | ITA-13903 |
| Path | `Extasy/ORC_2026_010a-26.pdf` |
| SHA-256 | `242d62596ef120f1a900edde8ca282595bfb16dec5d593e553c09355f648df53` |
| Research purpose | Certified 2026 ORC performance and measurement record for Extasy |
| Source limits | Safari print of `https://sas.orc.org/sasapi/cc/261982` on 21 October 2026, not an ORC-generated PDF. The print includes the page URL. The file metadata author is the person who printed it. Blank fields and N/A values are left blank. Page 3, read from the rendered page, prints P 14.710, E 5.370, J 4.420, and I as N/A. A text extract that reads P as 4.710 dropped the leading digit. Page 4 lists mainsail 1, headsails jib2 and 1, and asymmetric 0. Those rows are certificate-listed sails, not a confirmed onboard inventory. |

## Verified hull and rig

Stored on the vessel profile by M2.6.3. Certificate numbers are not registration numbers. I and LWL are unknown.

| Vessel | LOA | Beam | Draft | Displacement | J | P | E |
|---|---|---|---|---|---|---|---|
| Extasy | 11.924 m | 3.770 m | 2.425 m | 7,272 kg | 4.420 m | 14.710 m | 5.370 m |
| Nimana | 13.600 m | 4.352 m | 2.108 m | 12,888 kg | 5.510 m | 16.550 m | 5.450 m |

## Extasy — Farr manufacturer VPP

| Field | Value |
| --- | --- |
| Vessel | Design #354, Beneteau First 40.7, racing version, for Chantiers Beneteau |
| Document title | DESIGN #354 — Beneteau First 40.7 Racing Version |
| Document type | Historical manufacturer VPP. Not an ORC certificate. |
| Certificate number | None |
| Issuer or author | Farr Yacht Design, Ltd. Copyright line: Bruce Farr & Associates, Inc., 1997 |
| Issue date | Cover date May 3, 2001. Page stamp 10/22/02. No validity period is printed. |
| VPP version | V2.87. Source file printed as `354OWNRC.VPP` |
| Path | `Extasy/Farr_Design_354_Performance_Prediction.pdf` |
| SHA-256 | `a66c8d8e1a970f3cfcb6dccfb867ab006415d52886828ec724acc894ff84b104` |
| Research purpose | Original manufacturer performance prediction for the First 40.7 racing version |
| Source limits | Cover spells “Benetau” once. Body text uses Beneteau. Wind is at masthead height, rough water. The legend describes a Course Times page that is not in this 11-page file. Best Performance rows for 30 kt stop at TWA 130° on PDF page 10. PDF page 11 is only the footer. |

## Nimana — ORC Club Certificate

| Field | Value |
| --- | --- |
| Vessel | Nimana, Bavaria Cruiser 46 |
| Document title | ORC Certificate for Nimana |
| Document type | ORC Club Certificate |
| Certificate number | 009/26 |
| ORC reference | 03850004N6F |
| Issuer | ORC, issued through ORC Bulgaria, Varna |
| Issue date | 27/04/2026, as printed |
| Validity | Valid until 31/12/2026 |
| VPP version | 2026 1.00 |
| Sail number | BUL 46 |
| Path | `Nimana/ORC_2026_009-26.pdf` |
| SHA-256 | `c36106066cd3fefb9183738d6b381e1ee16cbeb53ddbe31712dd80228a567848` |
| Research purpose | Certified 2026 ORC performance and measurement record for Nimana |
| Source limits | Safari print of `https://sas.orc.org/sasapi/cc/252853` on 21 October 2026, not an ORC-generated PDF. The print includes the page URL. No manufacturer VPP is attached. The certificate prints class Bavaria Cruiser 46 and offset file `BAVARIACR45.off`. Both are kept as printed. Page 3, read from the rendered page, prints P 16.550, E 5.450, J 5.510, and I as N/A. A text extract that reads P as 6.550 dropped the leading digit. Page 4 lists mainsail 0, headsail 0, and three asymmetric sails: 0, 11, and A0. Those rows stay separate and are certificate-listed, not a confirmed onboard inventory. |

## Not registered

Two other files were in the Cursor upload and are not these certificates:

- `Magistarska_Teza_Purvonachalen_Plan.pdf` is the thesis working plan, revision 0.1, 21 October 2026.
- `Magistarska_Teza_Plan_Rev_0_2.pdf` is the same plan, revision 0.2.

They were not copied here.
