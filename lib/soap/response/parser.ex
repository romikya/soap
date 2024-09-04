defmodule Soap.Response.Parser do
  @moduledoc """
  Provides a functions for parse an XML-like response body.
  """

  import SweetXml, only: [xpath: 2, sigil_x: 2]

  @doc """
  Executing with XML response body.

  If a list is empty then `parse/1` returns full parsed response structure into map.
  """
  @spec parse(String.t(), atom()) :: map()
  def parse(xml_response, :fault) do
    fault_tag = get_fault_tag(xml_response)

    xml_response
    |> xpath(~x"//#{fault_tag}/*"l)
    |> parse_elements()
  end

  def parse(xml_response, _response_type) do
    body_tag = get_body_tag(xml_response)

    xml_response
    |> xpath(~x"//#{body_tag}/*"l)
    |> parse_elements()
  end

  @spec parse_record(tuple()) :: map() | String.t()
  defp parse_record({:xmlElement, tag_name, _, _, _, _, _, [], elements, _, _, _}) do
    %{tag_name => parse_elements(elements)}
  end

  defp parse_record({:xmlElement, tag_name, _, _, _, _, _, attributes, elements, _, _, _}) when is_list(attributes) do
    if is_nil_attribute_present?(attributes) do
      %{tag_name => nil}
    else
      %{tag_name => parse_elements(elements)}
    end
  end

  defp parse_record({:xmlText, _, _, _, value, _}), do: transform_record_value(value)

  defp transform_record_value(nil), do: nil
  defp transform_record_value(value) when is_list(value), do: value |> to_string() |> String.trim()
  defp transform_record_value(value) when is_binary(value), do: value |> String.trim()

  @spec parse_elements(list() | tuple()) :: map()
  defp parse_elements([]), do: %{}

  defp parse_elements(elements) when is_tuple(elements) do
    elements
    |> parse_record
  end

  defp parse_elements(elements) when is_list(elements) do
    elements
    |> Enum.map(&parse_record/1)
    |> parse_element_values()
  end

  @spec parse_element_values(list()) :: any()
  defp parse_element_values(elements) do
    cond do
      Enum.all?(elements, &is_map/1) && unique_tags?(elements) ->
        Enum.reduce(elements, &Map.merge/2)

      Enum.all?(elements, &is_map/1) ->
        elements |> Enum.map(&Map.to_list/1) |> List.flatten()

      true ->
        extract_value_from_list(elements)
    end
  end

  @spec extract_value_from_list(list()) :: any()
  defp extract_value_from_list([element]), do: element
  defp extract_value_from_list(elements), do: elements

  defp unique_tags?(elements) do
    keys =
      elements
      |> Enum.map(&Map.keys/1)
      |> List.flatten()

    Enum.uniq(keys) == keys
  end

  @spec is_nil_attribute_present?(list()) :: boolean()
  defp is_nil_attribute_present?([{:xmlAttribute, :"xsi:nil", _, _, _, _, _, _, ~c"true", _}, _t]), do: true
  defp is_nil_attribute_present?([{:xmlAttribute, :"xsi:nil", _, _, _, _, _, _, ~c"true", _}]), do: true
  defp is_nil_attribute_present?([_h | t]), do: is_nil_attribute_present?(t)
  defp is_nil_attribute_present?([]), do: false

  defp get_envelope_namespace(xml_response) do
    env_namespace = Soap.get_namespace_atoms()

    xml_response
    |> xpath(~x"//namespace::*"l)
    |> Enum.find(fn {_, _, _, _, namespace_url} -> namespace_url == env_namespace end)
    |> elem(3)
  end

  defp get_fault_tag(xml_response) do
    xml_response
    |> get_envelope_namespace()
    |> List.to_string()
    |> apply_namespace_to_tag("Fault")
  end

  defp get_body_tag(xml_response) do
    xml_response
    |> get_envelope_namespace()
    |> List.to_string()
    |> apply_namespace_to_tag("Body")
  end

  defp apply_namespace_to_tag("", tag), do: tag
  defp apply_namespace_to_tag(env_namespace, tag), do: env_namespace <> ":" <> tag
end
