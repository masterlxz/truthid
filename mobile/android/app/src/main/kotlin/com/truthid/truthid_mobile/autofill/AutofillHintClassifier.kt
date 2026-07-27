package com.truthid.truthid_mobile.autofill

import android.view.View

/**
 * Papel específico de um campo dentro de um formulário — mais granular que
 * o `EntryType` do Vault (Dart/Rust/TS): dois campos do mesmo tipo (ex:
 * username e password, ambos "credential") ainda precisam ser distinguidos
 * pra saber qual `AutofillId` recebe qual valor na hora de montar o
 * `Dataset` final (`TruthIdAutofillService`).
 */
enum class FieldRole {
    USERNAME,
    PASSWORD,
    EMAIL,
    FULL_NAME,
    STREET_ADDRESS,
    POSTAL_CODE,
    LOCALITY,
    REGION,
    COUNTRY,
    PHONE,
    CARD_NUMBER,
    CARD_EXPIRATION_DATE, // campo único MM/AA — ver comentário em classifyHint
    CARD_EXPIRATION_MONTH,
    CARD_EXPIRATION_YEAR,
    CARD_SECURITY_CODE,
}

// Mesmos 3 valores que `VaultEntry.type` já usa nos 3 lados existentes
// (Dart/Rust/TS) — string crua, não enum Kotlin, porque atravessa o
// MethodChannel como está (sem precisar de um (de)serializador à parte só
// pra essa ponte).
const val ENTRY_TYPE_CREDENTIAL = "credential"
const val ENTRY_TYPE_ADDRESS = "address"
const val ENTRY_TYPE_CREDIT_CARD = "creditCard"

fun entryTypeForRole(role: FieldRole): String = when (role) {
    FieldRole.USERNAME, FieldRole.PASSWORD, FieldRole.EMAIL -> ENTRY_TYPE_CREDENTIAL
    FieldRole.FULL_NAME, FieldRole.STREET_ADDRESS, FieldRole.POSTAL_CODE,
    FieldRole.LOCALITY, FieldRole.REGION, FieldRole.COUNTRY, FieldRole.PHONE -> ENTRY_TYPE_ADDRESS
    FieldRole.CARD_NUMBER, FieldRole.CARD_EXPIRATION_DATE, FieldRole.CARD_EXPIRATION_MONTH,
    FieldRole.CARD_EXPIRATION_YEAR, FieldRole.CARD_SECURITY_CODE -> ENTRY_TYPE_CREDIT_CARD
}

// `View.AUTOFILL_HINT_POSTAL_ADDRESS_*` de campo único (rua/cidade/estado/
// país separados) não existe no conjunto base de constantes de
// `android.view.View` (API 26) — só o hint combinado `POSTAL_ADDRESS`
// existe lá. Os hints granulares que apps de checkout modernos realmente
// declaram (ex: Chrome) vêm de `androidx.autofill.HintConstants`, que são
// só literais de string estáveis — hardcoded aqui pra não puxar essa
// dependência nova só por causa de 4 constantes.
private const val HINT_POSTAL_ADDRESS_STREET_ADDRESS = "postalAddressStreetAddress"
private const val HINT_POSTAL_ADDRESS_LOCALITY = "postalAddressLocality"
private const val HINT_POSTAL_ADDRESS_REGION = "postalAddressRegion"
private const val HINT_POSTAL_ADDRESS_COUNTRY = "postalAddressCountry"

/**
 * Classifica um único token de `autofillHints`. `null` pra hints sem papel
 * conhecido — o campo é ignorado (sem heurística de fallback por texto/tipo
 * nesta fatia, ver `project/PHASE.md` 15.5).
 *
 * `AUTOFILL_HINT_POSTAL_ADDRESS` (hint combinado, 1 campo só pro endereço
 * inteiro) mapeia pra `STREET_ADDRESS` — melhor esforço: um formulário que
 * só declara esse hint combinado recebe só a rua+número no preenchimento
 * (mesma limitação que `addressFill.ts`, extensão, já aceita pro caso
 * equivalente do navegador).
 */
fun classifyHint(hint: String): FieldRole? = when (hint) {
    View.AUTOFILL_HINT_USERNAME -> FieldRole.USERNAME
    View.AUTOFILL_HINT_PASSWORD -> FieldRole.PASSWORD
    View.AUTOFILL_HINT_EMAIL_ADDRESS -> FieldRole.EMAIL
    View.AUTOFILL_HINT_NAME -> FieldRole.FULL_NAME
    View.AUTOFILL_HINT_POSTAL_ADDRESS -> FieldRole.STREET_ADDRESS
    HINT_POSTAL_ADDRESS_STREET_ADDRESS -> FieldRole.STREET_ADDRESS
    View.AUTOFILL_HINT_POSTAL_CODE -> FieldRole.POSTAL_CODE
    HINT_POSTAL_ADDRESS_LOCALITY -> FieldRole.LOCALITY
    HINT_POSTAL_ADDRESS_REGION -> FieldRole.REGION
    HINT_POSTAL_ADDRESS_COUNTRY -> FieldRole.COUNTRY
    View.AUTOFILL_HINT_PHONE -> FieldRole.PHONE
    View.AUTOFILL_HINT_CREDIT_CARD_NUMBER -> FieldRole.CARD_NUMBER
    View.AUTOFILL_HINT_CREDIT_CARD_EXPIRATION_DATE -> FieldRole.CARD_EXPIRATION_DATE
    View.AUTOFILL_HINT_CREDIT_CARD_EXPIRATION_MONTH -> FieldRole.CARD_EXPIRATION_MONTH
    View.AUTOFILL_HINT_CREDIT_CARD_EXPIRATION_YEAR -> FieldRole.CARD_EXPIRATION_YEAR
    View.AUTOFILL_HINT_CREDIT_CARD_SECURITY_CODE -> FieldRole.CARD_SECURITY_CODE
    else -> null
}

/**
 * Um `View` pode declarar mais de um hint em `android:autofillHints`
 * (lista ordenada por prioridade, documentado pelo próprio framework) —
 * devolve o papel do primeiro token reconhecido.
 */
fun classifyHints(hints: List<String>): FieldRole? = hints.firstNotNullOfOrNull(::classifyHint)
