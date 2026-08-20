"use client"

import React, { useEffect, useState, useCallback } from "react";
import { useNavigate, useSearchParams } from "react-router";
import { Formik, Form, Field, ErrorMessage } from "formik";
import { metodoPagoEsquema } from "../../validaciones/metodoPagoEsquema";
import api from "../../api/axiosConfig";
import Boton from "../../componentes/comunes/Boton";
import { toast } from "react-toastify";
import { Search } from "lucide-react";
import type { MetodoPagoResponse } from "../../types/types";
import { normalizeMoneyInput } from "../../utils/money";

interface MetodoPago {
  id?: number;
  descripcion: string;
  recargo: string;
}

const initialValues: MetodoPago = {
  descripcion: "",
  recargo: "0",
};

const MetodosPagoFormulario: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();

  // Estado para almacenar los valores del formulario
  const [formValues, setFormValues] = useState<MetodoPago>(initialValues);

  // Función para buscar y actualizar los valores
  const handleBuscar = useCallback(async (idStr: string) => {
    try {
      const idNum = Number(idStr);
      if (isNaN(idNum)) {
        toast.error("ID inválido");
        return;
      }
      const response = await api.get<MetodoPagoResponse>(`/metodos-pago/${idNum}`);
      setFormValues({ id: response.data.id, descripcion: response.data.descripcion, recargo: response.data.recargo });
      toast.success("Método de pago cargado correctamente.");
    } catch {
      toast.error("Error al cargar los datos del método de pago.");
      setFormValues(initialValues);
    }
  }, []);

  // Si existe un id en la URL, cargar los datos al montar el componente
  useEffect(() => {
    const id = searchParams.get("id");
    if (id) {
      handleBuscar(id);
    }
  }, [searchParams, handleBuscar]);

  const handleGuardar = async (values: MetodoPago) => {
    const payload = {
      ...values,
      recargo: normalizeMoneyInput(String(values.recargo)) ?? String(values.recargo),
    };
    try {
      if (values.id) {
        await api.put(`/metodos-pago/${values.id}`, payload);
        toast.success("Método de pago actualizado correctamente.");
      } else {
        await api.post("/metodos-pago", payload);
        toast.success("Método de pago creado correctamente.");
      }
    } catch {
      toast.error("Error al guardar los datos del método de pago.");
    }
  };

  return (
    <div className="page-container">
      <h1 className="page-title">
        {searchParams.get("id") ? "Editar Método de Pago" : "Nuevo Método de Pago"}
      </h1>
      <Formik
        initialValues={formValues}
        validationSchema={metodoPagoEsquema}
        onSubmit={handleGuardar}
        enableReinitialize
      >
        {({ resetForm, isSubmitting, values }) => (
          <Form className="formulario max-w-4xl mx-auto">
            <div className="form-grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="col-span-full mb-4">
                <label htmlFor="idBusqueda" className="auth-label">
                  Número de Método de Pago:
                </label>
                <div className="flex gap-2">
                  <Field
                    type="number"
                    id="idBusqueda"
                    name="id"
                    className="form-input flex-grow"
                    onChange={(e: React.ChangeEvent<HTMLInputElement>) =>
                      // Actualizamos temporalmente el campo id y buscamos
                      handleBuscar(e.target.value)
                    }
                  />
                  <Boton
                    onClick={() =>
                      handleBuscar(values.id?.toString() || "")
                    }
                    className="page-button"
                  >
                    <Search className="w-5 h-5 mr-2" />
                    Buscar
                  </Boton>
                </div>
              </div>

              <div className="col-span-full mb-4">
                <label htmlFor="descripcion" className="auth-label">
                  Descripción:
                </label>
                <Field name="descripcion" type="text" id="descripcion" className="form-input" />
                <ErrorMessage name="descripcion" component="div" className="auth-error" />
              </div>
              <div className="col-span-full mb-4">
                <label htmlFor="recargo" className="auth-label">
                  Recargo:
                </label>
                <Field name="recargo" type="number" id="recargo" className="form-input" />
                <ErrorMessage name="recargo" component="div" className="auth-error" />
              </div>
            </div>

            <div className="form-acciones">
              <Boton type="submit" disabled={isSubmitting} className="page-button">
                Guardar Método de Pago
              </Boton>
              <Boton
                type="reset"
                onClick={() => {
                  resetForm({ values: initialValues });
                  setFormValues(initialValues);
                }}
                className="page-button-secondary"
              >
                Limpiar
              </Boton>
              <Boton
                type="button"
                onClick={() => navigate("/metodos-pago")}
                className="page-button-secondary"
              >
                Volver al Listado
              </Boton>
            </div>
          </Form>
        )}
      </Formik>
    </div>
  );
};

export default MetodosPagoFormulario;
