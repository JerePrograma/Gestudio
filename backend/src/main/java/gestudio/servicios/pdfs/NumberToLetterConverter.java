package gestudio.servicios.pdfs;

public class NumberToLetterConverter {

    private static final String[] UNIDADES = {
            "", "uno", "dos", "tres", "cuatro", "cinco",
            "seis", "siete", "ocho", "nueve", "diez", "once",
            "doce", "trece", "catorce", "quince", "dieciseis",
            "diecisiete", "dieciocho", "diecinueve", "veinte"
    };

    private static final String[] DECENAS = {
            "", "", "veinti", "treinta", "cuarenta", "cincuenta",
            "sesenta", "setenta", "ochenta", "noventa"
    };

    private static final String[] CENTENAS = {
            "", "ciento", "doscientos", "trescientos", "cuatrocientos",
            "quinientos", "seiscientos", "setecientos", "ochocientos", "novecientos"
    };

    public static String convertir(long numero) {
        if (numero == 0) return "cero";
        if (numero == 100) return "cien";

        StringBuilder resultado = new StringBuilder();

        if (numero >= 1_000_000) {
            long millones = numero / 1_000_000;
            resultado.append(convertir(millones)).append(" millon");
            if (millones > 1) resultado.append("es");
            numero %= 1_000_000;
            resultado.append(" ");
        }

        if (numero >= 1000) {
            long miles = numero / 1000;
            if (miles > 1) resultado.append(convertir(miles)).append(" ");
            resultado.append("mil ");
            numero %= 1000;
        }

        if (numero >= 100) {
            long centenas = numero / 100;
            resultado.append(CENTENAS[(int) centenas]).append(" ");
            numero %= 100;
        }

        if (numero > 20) {
            int decenas = (int) numero / 10;
            int unidades = (int) numero % 10;
            resultado.append(DECENAS[decenas]);
            if (decenas == 2 && unidades > 0) {
                resultado.append(UNIDADES[unidades]);
            } else if (unidades > 0) {
                resultado.append(" y ").append(UNIDADES[unidades]);
            }
        } else if (numero > 0) {
            resultado.append(UNIDADES[(int) numero]);
        }

        return resultado.toString().trim();
    }
}
