Direccionable
Página principal
github.com/sporkmonger/addressable
Autor
Bob Aman
Derechos de autor
Copyright © Bob Aman
Licencia
Apache 2.0
Versión de gema Estado de la construcción Estado de cobertura de prueba Estado de la cobertura de la documentación

Descripción
Addressable es una implementación alternativa a la implementación de URI que forma parte de la biblioteca estándar de Ruby. Es flexible, ofrece análisis heurístico y, además, proporciona un amplio soporte para plantillas de IRI y URI.

Direccionable se ajusta estrechamente a RFC 3986, RFC 3987 y RFC 6570 (nivel 4).

Referencia
{Direccionable :: URI}
{Direccionable :: Plantilla}
Uso de ejemplo
requieren  "direccionable / uri"

uri  =  Direccionable :: URI . parse ( "http://example.com/path/to/resource/" ) 
uri . esquema 
# => "http" 
uri . host 
# => "example.com" 
uri . ruta 
# => "/ ruta / a / recurso /"

uri  =  Direccionable :: URI . parse ( "http: // www. 詹姆斯 .com /" ) 
uri . normalizar 
# => # <Direccionable :: URI: 0xc9a4c8 URI: http: //www.xn--8ws00zhy3a.com/>
Plantillas de URI
Para obtener más detalles, consulte RFC 6570 .

requieren  "direccionable / plantilla"

template  =  Direccionable :: Plantilla . plantilla nueva ( "http://example.com/{?query*}" ) 
. expand ( { "query" => { 'foo' => 'bar' , 'color' => 'red' } } ) # => # <Addressable :: URI: 0xc9d95c URI: http: //example.com/ ? foo = bar & color = red>
    
      
      
  



template  =  Direccionable :: Plantilla . plantilla nueva ( "http://example.com/{?one,two,three}" ) 
. expansión_parcial ( { "uno" => "1" , "tres" => 3 } ) . patrón # => "http://example.com/?one=1{&two}&three=3"     


template  =  Direccionable :: Plantilla . nuevo ( 
  "http: // {host} {/ segmentos *} / {? uno, dos, falso} {#fragmento}" 
) 
uri  =  Direccionable :: URI . parse ( 
  "http://example.com/a/b/c/?one=1&two=2#foo" 
) 
plantilla . extraer ( uri ) 
# => 
# { 
# "host" => "ejemplo.com", 
# "segmentos" => ["a", "b", "c"], 
# "uno" => "1" , 
# "dos" => "2", 
# "fragmento" => "foo"
Instalar en pc
$ gem install direccionable
Opcionalmente, puede activar la compatibilidad con IDN nativos instalando libidn y la gema idn:

$ sudo apt-get install libidn11-dev # Debian / Ubuntu 
$ brew install libidn # OS X 
$ gem install idn-ruby
Control de versiones semántico
Este proyecto utiliza control de versiones semántico . Puede (y debe) especificar su dependencia utilizando una restricción de versión pesimista que cubra los valores mayor y menor:

espec . add_dependency  'direccionable' ,  '~> 2.7'
Si necesita una corrección de error específica, también puede especificar versiones mínimas mínimas sin evitar las actualizaciones de la última versión menor:

espec . add_dependency  'direccionabl
