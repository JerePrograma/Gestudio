import { useMemo } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ErrorMessage, Field, Form, Formik, type FormikHelpers } from "formik";
import { useNavigate, useSearchParams } from "react-router-dom";
import { toast } from "react-toastify";
import { getApiErrorMessage, getFieldErrors } from "../../api/apiError";
import stocksApi from "../../api/stocksApi";
import Boton from "../../componentes/comunes/Boton";
import ErrorState from "../../componentes/comunes/ErrorState";
import LoadingState from "../../componentes/comunes/LoadingState";
import MoneyInput from "../../componentes/comunes/MoneyInput";
import { queryKeys } from "../../hooks/queryKeys";
import type { StockModificacionRequest, StockRegistroRequest } from "../../types/types";
import { normalizeMoneyInput } from "../../utils/money";
import { stockEsquema } from "../../validaciones/stockEsquema";
import PageHeader from "../../componentes/comunes/PageHeader";
import SectionCard from "../../componentes/comunes/SectionCard";

type StockForm = Omit<StockModificacionRequest, "idempotencyKey">;

const VACIO: StockForm = {
  nombre: "",
  precio: "",
  stock: 0,
  requiereControlDeStock: false,
  codigoBarras: "",
  activo: true,
};

export default function StocksFormulario() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams] = useSearchParams();
  const id = Number(searchParams.get("id")) || undefined;
  const detalle = useQuery({
    queryKey: queryKeys.stock(id ?? 0),
    queryFn: () => stocksApi.obtenerStockPorId(id!),
    enabled: id !== undefined,
  });
  const inicial = useMemo<StockForm>(() => detalle.data ? {
    nombre: detalle.data.nombre,
    precio: detalle.data.precio,
    stock: detalle.data.stock,
    requiereControlDeStock: detalle.data.requiereControlDeStock,
    codigoBarras: detalle.data.codigoBarras,
    activo: detalle.data.activo,
  } : VACIO, [detalle.data]);

  const guardar = async (values: StockForm, helpers: FormikHelpers<StockForm>) => {
    const request: StockRegistroRequest = {
      ...values,
      precio: normalizeMoneyInput(values.precio) ?? values.precio,
      idempotencyKey: crypto.randomUUID(),
    };
    try {
      if (id) await stocksApi.actualizarStock(id, { ...request, activo: values.activo });
      else await stocksApi.registrarStock(request);
      await queryClient.invalidateQueries({ queryKey: queryKeys.all.stocks });
      toast.success(id ? "Producto actualizado" : "Producto creado");
      navigate("/stocks");
    } catch (error) {
      helpers.setErrors(getFieldErrors(error));
      toast.error(getApiErrorMessage(error, "No se pudo guardar el producto."));
    } finally {
      helpers.setSubmitting(false);
    }
  };

  if (detalle.isLoading) return <LoadingState message="Cargando producto..." />;
  if (detalle.isError) return <ErrorState message="No se pudo cargar el producto." onRetry={() => void detalle.refetch()} />;

  return <main className="page-container">
    <PageHeader eyebrow="Inventario" title={id ? "Editar producto" : "Nuevo producto"} description="Definí los datos comerciales y el control de disponibilidad." />
    <Formik initialValues={inicial} validationSchema={stockEsquema} onSubmit={guardar} enableReinitialize>
      {({ errors, isSubmitting, setFieldValue, values }) => <Form className="mx-auto max-w-4xl space-y-5" noValidate>
        <SectionCard title="Datos del producto" description="Información visible en stock y operaciones.">
        <div className="form-grid">
        <label className="field-group">Nombre<Field className="form-input" name="nombre" /><ErrorMessage className="form-error" name="nombre" component="span" /></label>
        <MoneyInput id="precio" label="Precio" value={values.precio} error={errors.precio} onChange={(value) => void setFieldValue("precio", value)} required />
        <label className="field-group">Cantidad<Field className="form-input" name="stock" type="number" min="0" /><ErrorMessage className="form-error" name="stock" component="span" /></label>
        <label className="field-group">Código de barras<Field className="form-input" name="codigoBarras" /></label>
        <label className="checkbox-field"><Field name="requiereControlDeStock" type="checkbox" /> <span><strong className="block">Requiere control de stock</strong><span className="mt-1 block text-xs font-normal text-muted-foreground">Activa el seguimiento de existencias.</span></span></label>
        {id && <label className="checkbox-field"><Field name="activo" type="checkbox" /> <span><strong className="block">Producto activo</strong><span className="mt-1 block text-xs font-normal text-muted-foreground">Disponible para las operaciones del sistema.</span></span></label>}
        </div>
        </SectionCard>
        <div className="form-acciones">
          <Boton type="button" className="page-button-secondary" onClick={() => navigate("/stocks")}>Cancelar</Boton>
          <Boton type="submit" className="page-button" disabled={isSubmitting}>{isSubmitting ? "Guardando..." : "Guardar producto"}</Boton>
        </div>
      </Form>}
    </Formik>
  </main>;
}
