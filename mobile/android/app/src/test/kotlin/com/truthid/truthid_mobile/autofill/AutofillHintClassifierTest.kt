package com.truthid.truthid_mobile.autofill

import android.view.View
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

// Testes JVM puros (`src/test`, não `src/androidTest`) — rodam contra o
// android.jar de stub que a AGP já injeta em `testImplementation`
// automaticamente. Constantes como `View.AUTOFILL_HINT_USERNAME` são
// literais de String inlined em tempo de compilação, então funcionam
// mesmo no stub (que só lança em métodos reais, não em campos estáticos
// finais) — sem precisar de Robolectric pra isto.
class AutofillHintClassifierTest {

    @Test
    fun `classifica hints de credencial`() {
        assertEquals(FieldRole.USERNAME, classifyHint(View.AUTOFILL_HINT_USERNAME))
        assertEquals(FieldRole.PASSWORD, classifyHint(View.AUTOFILL_HINT_PASSWORD))
        assertEquals(FieldRole.EMAIL, classifyHint(View.AUTOFILL_HINT_EMAIL_ADDRESS))
    }

    @Test
    fun `classifica hints de endereco, incluindo os granulares hardcoded`() {
        assertEquals(FieldRole.FULL_NAME, classifyHint(View.AUTOFILL_HINT_NAME))
        assertEquals(FieldRole.STREET_ADDRESS, classifyHint(View.AUTOFILL_HINT_POSTAL_ADDRESS))
        assertEquals(FieldRole.STREET_ADDRESS, classifyHint("postalAddressStreetAddress"))
        assertEquals(FieldRole.POSTAL_CODE, classifyHint(View.AUTOFILL_HINT_POSTAL_CODE))
        assertEquals(FieldRole.LOCALITY, classifyHint("postalAddressLocality"))
        assertEquals(FieldRole.REGION, classifyHint("postalAddressRegion"))
        assertEquals(FieldRole.COUNTRY, classifyHint("postalAddressCountry"))
        assertEquals(FieldRole.PHONE, classifyHint(View.AUTOFILL_HINT_PHONE))
    }

    @Test
    fun `classifica hints de cartao de credito`() {
        assertEquals(FieldRole.CARD_NUMBER, classifyHint(View.AUTOFILL_HINT_CREDIT_CARD_NUMBER))
        assertEquals(
            FieldRole.CARD_EXPIRATION_DATE,
            classifyHint(View.AUTOFILL_HINT_CREDIT_CARD_EXPIRATION_DATE),
        )
        assertEquals(
            FieldRole.CARD_EXPIRATION_MONTH,
            classifyHint(View.AUTOFILL_HINT_CREDIT_CARD_EXPIRATION_MONTH),
        )
        assertEquals(
            FieldRole.CARD_EXPIRATION_YEAR,
            classifyHint(View.AUTOFILL_HINT_CREDIT_CARD_EXPIRATION_YEAR),
        )
        assertEquals(
            FieldRole.CARD_SECURITY_CODE,
            classifyHint(View.AUTOFILL_HINT_CREDIT_CARD_SECURITY_CODE),
        )
    }

    @Test
    fun `hint desconhecido devolve null`() {
        assertNull(classifyHint("something-truthid-does-not-recognize"))
        assertNull(classifyHint(""))
    }

    @Test
    fun `classifyHints devolve o primeiro token reconhecido, ignora os outros`() {
        assertEquals(
            FieldRole.PASSWORD,
            classifyHints(listOf("something-unknown", View.AUTOFILL_HINT_PASSWORD)),
        )
    }

    @Test
    fun `classifyHints devolve null quando nenhum token e reconhecido`() {
        assertNull(classifyHints(listOf("a", "b", "c")))
    }

    @Test
    fun `classifyHints devolve null pra lista vazia`() {
        assertNull(classifyHints(emptyList()))
    }

    @Test
    fun `entryTypeForRole mapeia cada papel pro EntryType certo`() {
        assertEquals(ENTRY_TYPE_CREDENTIAL, entryTypeForRole(FieldRole.USERNAME))
        assertEquals(ENTRY_TYPE_CREDENTIAL, entryTypeForRole(FieldRole.PASSWORD))
        assertEquals(ENTRY_TYPE_CREDENTIAL, entryTypeForRole(FieldRole.EMAIL))
        assertEquals(ENTRY_TYPE_ADDRESS, entryTypeForRole(FieldRole.FULL_NAME))
        assertEquals(ENTRY_TYPE_ADDRESS, entryTypeForRole(FieldRole.STREET_ADDRESS))
        assertEquals(ENTRY_TYPE_ADDRESS, entryTypeForRole(FieldRole.POSTAL_CODE))
        assertEquals(ENTRY_TYPE_ADDRESS, entryTypeForRole(FieldRole.LOCALITY))
        assertEquals(ENTRY_TYPE_ADDRESS, entryTypeForRole(FieldRole.REGION))
        assertEquals(ENTRY_TYPE_ADDRESS, entryTypeForRole(FieldRole.COUNTRY))
        assertEquals(ENTRY_TYPE_ADDRESS, entryTypeForRole(FieldRole.PHONE))
        assertEquals(ENTRY_TYPE_CREDIT_CARD, entryTypeForRole(FieldRole.CARD_NUMBER))
        assertEquals(ENTRY_TYPE_CREDIT_CARD, entryTypeForRole(FieldRole.CARD_EXPIRATION_DATE))
        assertEquals(ENTRY_TYPE_CREDIT_CARD, entryTypeForRole(FieldRole.CARD_EXPIRATION_MONTH))
        assertEquals(ENTRY_TYPE_CREDIT_CARD, entryTypeForRole(FieldRole.CARD_EXPIRATION_YEAR))
        assertEquals(ENTRY_TYPE_CREDIT_CARD, entryTypeForRole(FieldRole.CARD_SECURITY_CODE))
    }
}
