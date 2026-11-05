/// OpenAPI 3.0.3 document for the POS API, rendered at /swagger.
/// Kept as a JSON string so it can be served verbatim.
const openApiSpecJson = r'''
{
  "openapi": "3.0.3",
  "info": {
    "title": "POS API",
    "version": "1.0.0",
    "description": "Point-of-sale backend (Dart Frog + MongoDB). All responses use the envelope {\"success\": true, \"status_code\": n, \"data\": ...} or {\"success\": false, \"error\": \"...\"}. Authenticate via POST /api/v1/account/auth/login, then send the returned token as \"Authorization: Bearer <token>\". Role 1 = Admin (guards /api/v1/admin/*), role 2 = Cashier (guards /api/v1/cashier/*). QR payments go through CutLuy or ABA PayWay, chosen by the PAYMENT_PROVIDER setting; /api/v1/payments/callback is the one route that is public because the gateway posts to it."
  },
  "servers": [
    {
      "url": "/",
      "description": "This server"
    }
  ],
  "tags": [
    {
      "name": "Health"
    },
    {
      "name": "Auth"
    },
    {
      "name": "Profile"
    },
    {
      "name": "Cashier"
    },
    {
      "name": "Payments"
    },
    {
      "name": "Admin / Products"
    },
    {
      "name": "Admin / Types"
    },
    {
      "name": "Admin / Sales"
    },
    {
      "name": "Admin / Users"
    },
    {
      "name": "Admin / Dashboard"
    },
    {
      "name": "Reports"
    },
    {
      "name": "Testing"
    }
  ],
  "security": [
    {
      "bearerAuth": []
    }
  ],
  "paths": {
    "/": {
      "get": {
        "tags": [
          "Health"
        ],
        "security": [],
        "summary": "Service health",
        "responses": {
          "200": {
            "description": "Service is up",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "object",
                          "properties": {
                            "service": {
                              "type": "string"
                            },
                            "status": {
                              "type": "string"
                            },
                            "time": {
                              "type": "string"
                            }
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/healthz": {
      "get": {
        "tags": [
          "Health"
        ],
        "security": [],
        "summary": "Liveness probe (no dependencies checked)",
        "responses": {
          "200": {
            "description": "Process is serving",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          }
        }
      }
    },
    "/readyz": {
      "get": {
        "tags": [
          "Health"
        ],
        "security": [],
        "summary": "Readiness probe (fails while MongoDB is unreachable)",
        "responses": {
          "200": {
            "description": "Service can handle requests",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "503": {
            "description": "Dependency unavailable",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/ErrorEnvelope"
                }
              }
            }
          }
        }
      }
    },
    "/api/v1/account/auth/login": {
      "post": {
        "tags": [
          "Auth"
        ],
        "security": [],
        "summary": "Login with username and password",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/LoginRequest"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "JWT returned",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/TokenResponse"
                        },
                        "message": {
                          "type": "string"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "401": {
            "$ref": "#/components/responses/Unauthorized"
          },
          "422": {
            "$ref": "#/components/responses/InvalidEntity"
          }
        }
      }
    },
    "/api/v1/account/auth/switch": {
      "post": {
        "tags": [
          "Auth"
        ],
        "summary": "Switch active role, returns a new token",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "role_id"
                ],
                "properties": {
                  "role_id": {
                    "type": "integer",
                    "enum": [
                      1,
                      2
                    ],
                    "example": 2
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "New token for the selected role",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/TokenResponse"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "403": {
            "$ref": "#/components/responses/Forbidden"
          }
        }
      }
    },
    "/api/v1/account/profile": {
      "get": {
        "tags": [
          "Profile"
        ],
        "summary": "Current user profile",
        "responses": {
          "200": {
            "description": "Profile",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/User"
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/v1/account/profile/update": {
      "put": {
        "tags": [
          "Profile"
        ],
        "summary": "Update own profile",
        "requestBody": {
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "name": {
                    "type": "string"
                  },
                  "phone": {
                    "type": "string"
                  },
                  "email": {
                    "type": "string"
                  },
                  "avatar": {
                    "type": "string",
                    "description": "base64 image; forwarded to the file service"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Updated profile",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/User"
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/v1/account/profile/update-password": {
      "put": {
        "tags": [
          "Profile"
        ],
        "summary": "Change own password",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "old_password",
                  "new_password"
                ],
                "properties": {
                  "old_password": {
                    "type": "string"
                  },
                  "new_password": {
                    "type": "string"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "400": {
            "$ref": "#/components/responses/BadRequest"
          }
        }
      }
    },
    "/api/v1/account/profile/logs": {
      "get": {
        "tags": [
          "Profile"
        ],
        "summary": "Own login history (paginated)",
        "parameters": [
          {
            "$ref": "#/components/parameters/Page"
          },
          {
            "$ref": "#/components/parameters/Limit"
          },
          {
            "$ref": "#/components/parameters/Key"
          },
          {
            "$ref": "#/components/parameters/SortBy"
          },
          {
            "$ref": "#/components/parameters/Order"
          }
        ],
        "responses": {
          "200": {
            "description": "Login logs",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "$ref": "#/components/schemas/Paginated"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "$ref": "#/components/schemas/UserLog"
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/v1/cashier/ordering/products": {
      "get": {
        "tags": [
          "Cashier"
        ],
        "summary": "Ordering screen: product types with nested active products",
        "responses": {
          "200": {
            "description": "Types with products",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "allOf": [
                              {
                                "$ref": "#/components/schemas/ProductType"
                              },
                              {
                                "type": "object",
                                "properties": {
                                  "products": {
                                    "type": "array",
                                    "items": {
                                      "$ref": "#/components/schemas/Product"
                                    }
                                  }
                                }
                              }
                            ]
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/v1/cashier/ordering/order": {
      "post": {
        "tags": [
          "Cashier"
        ],
        "summary": "Checkout: create an order from a cart",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "cart"
                ],
                "properties": {
                  "cart": {
                    "description": "Mapping of product id to quantity, either a JSON string or an object",
                    "oneOf": [
                      {
                        "type": "string",
                        "example": "{\"64f1a0000000000000000001\": 2}"
                      },
                      {
                        "type": "object",
                        "additionalProperties": {
                          "type": "integer"
                        },
                        "example": {
                          "64f1a0000000000000000001": 2
                        }
                      }
                    ]
                  },
                  "platform": {
                    "type": "string",
                    "default": "Web"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": "Order placed; receipt number generated",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Order"
                        },
                        "message": {
                          "type": "string"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "400": {
            "$ref": "#/components/responses/BadRequest"
          },
          "422": {
            "$ref": "#/components/responses/InvalidEntity"
          }
        }
      }
    },
    "/api/v1/cashier/payments": {
      "post": {
        "tags": [
          "Cashier"
        ],
        "summary": "Show a QR code for a cart",
        "description": "Asks PayWay to generate a KHQR for the cart and records a pending payment. No sale and no receipt number exist yet: those appear only when PayWay confirms the payment, so an abandoned QR leaves no gap in the receipt sequence.",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "cart"
                ],
                "properties": {
                  "cart": {
                    "description": "Mapping of product id to quantity, either a JSON string or an object",
                    "oneOf": [
                      {
                        "type": "string",
                        "example": "{\"64f1a0000000000000000001\": 2}"
                      },
                      {
                        "type": "object",
                        "additionalProperties": {
                          "type": "integer"
                        },
                        "example": {
                          "64f1a0000000000000000001": 2
                        }
                      }
                    ]
                  },
                  "platform": {
                    "type": "string",
                    "default": "Web"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": "QR generated; payment pending",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Payment"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "400": {
            "$ref": "#/components/responses/BadRequest"
          },
          "422": {
            "$ref": "#/components/responses/InvalidEntity"
          },
          "502": {
            "$ref": "#/components/responses/BadGateway"
          },
          "503": {
            "$ref": "#/components/responses/ServiceUnavailable"
          }
        }
      }
    },
    "/api/v1/cashier/payments/{tranId}": {
      "get": {
        "tags": [
          "Cashier"
        ],
        "summary": "Refresh a payment from the gateway",
        "description": "Asks the configured gateway — CutLuy or PayWay — what became of the transaction and returns the stored result. A payment that turns out to be approved produces the sale at this point. A cashier only sees their own payments.",
        "parameters": [
          {
            "$ref": "#/components/parameters/TranIdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Current state of the payment",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Payment"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "401": {
            "$ref": "#/components/responses/Unauthorized"
          },
          "403": {
            "$ref": "#/components/responses/Forbidden"
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          },
          "502": {
            "$ref": "#/components/responses/BadGateway"
          },
          "503": {
            "$ref": "#/components/responses/ServiceUnavailable"
          }
        }
      }
    },
    "/api/v1/cashier/payments/{tranId}/qr": {
      "get": {
        "tags": [
          "Cashier"
        ],
        "summary": "The payment's QR code drawn as an image",
        "description": "Renders payment.qr_string — the raw KHQR payload — at error correction level H, which is what lets a till put a logo or a riel medallion over the centre of the code without breaking the scan. Nothing is asked of the gateway and no customer is sent to a hosted checkout page: the image is drawn here from the payload this service already holds, so a screen refresh costs no API call. Once a payment leaves pending its code is gone for good, and the answer is 410 rather than a picture of a code that can no longer be paid. The SVG carries module geometry only — the payload text is never written into the markup.",
        "parameters": [
          {
            "$ref": "#/components/parameters/TranIdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "The QR code for this payment, as SVG",
            "content": {
              "image/svg+xml": {
                "schema": {
                  "type": "string"
                }
              }
            }
          },
          "401": {
            "$ref": "#/components/responses/Unauthorized"
          },
          "403": {
            "$ref": "#/components/responses/Forbidden"
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          },
          "410": {
            "description": "The payment is paid, expired or refused, so its code is no longer drawn"
          }
        }
      }
    },
    "/api/v1/payments/callback": {
      "post": {
        "tags": [
          "Payments"
        ],
        "security": [],
        "summary": "Payment notification from the gateway",
        "description": "Public by necessity: the payments company posts here and cannot carry a cashier token. The body is verified as the bytes that arrived — CutLuy signs an HMAC over \"t.rawBody\", and a signature computed over re-serialised JSON never matches — and what the delivery claims about money is never believed: the transaction is re-read through the authenticated gateway API before a sale is written. The response goes out before that re-read, because a gateway that does not get a 2xx retries the delivery up to eight times.",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "oneOf": [
                  {
                    "$ref": "#/components/schemas/CutLuyEvent"
                  },
                  {
                    "$ref": "#/components/schemas/PaywayNotification"
                  }
                ]
              }
            }
          }
        },
        "responses": {
          "202": {
            "$ref": "#/components/responses/Accepted"
          },
          "400": {
            "$ref": "#/components/responses/BadRequest"
          },
          "401": {
            "$ref": "#/components/responses/Unauthorized"
          },
          "503": {
            "$ref": "#/components/responses/ServiceUnavailable"
          }
        },
        "parameters": [
          {
            "name": "X-CutLuy-Signature",
            "in": "header",
            "required": false,
            "description": "t=<unix>,v1=<hex>. Required when PAYMENT_PROVIDER is cutluy: a delivery that does not verify is refused.",
            "schema": {
              "type": "string",
              "example": "t=1720526591,v1=3f2a"
            }
          },
          {
            "name": "X-CutLuy-Event",
            "in": "header",
            "required": false,
            "description": "Event name. payment.completed means the customer paid; it is a reason to look, not proof.",
            "schema": {
              "type": "string",
              "enum": [
                "payment.completed",
                "payment.scanned",
                "payment.expired",
                "payment.failed"
              ]
            }
          }
        ]
      }
    },
    "/api/v1/cashier/sales": {
      "get": {
        "tags": [
          "Cashier"
        ],
        "summary": "Own sales history (paginated)",
        "parameters": [
          {
            "$ref": "#/components/parameters/Page"
          },
          {
            "$ref": "#/components/parameters/Limit"
          },
          {
            "$ref": "#/components/parameters/Key"
          },
          {
            "$ref": "#/components/parameters/SortBy"
          },
          {
            "$ref": "#/components/parameters/Order"
          },
          {
            "$ref": "#/components/parameters/Platform"
          },
          {
            "$ref": "#/components/parameters/StartDate"
          },
          {
            "$ref": "#/components/parameters/EndDate"
          }
        ],
        "responses": {
          "200": {
            "description": "Orders",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "$ref": "#/components/schemas/Paginated"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "$ref": "#/components/schemas/Order"
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/v1/cashier/sales/{id}": {
      "get": {
        "tags": [
          "Cashier"
        ],
        "summary": "View own order detail",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Order",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Order"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "delete": {
        "tags": [
          "Cashier"
        ],
        "summary": "Delete own order",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "403": {
            "$ref": "#/components/responses/Forbidden"
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/v1/reports/invoice/{id}": {
      "get": {
        "tags": [
          "Reports"
        ],
        "summary": "Download invoice PDF for an order",
        "description": "Returns an A4 invoice PDF with shaped Khmer text. Admins may request any order; cashiers only their own.",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Invoice PDF",
            "content": {
              "application/pdf": {
                "schema": {
                  "type": "string",
                  "format": "binary"
                }
              }
            }
          },
          "403": {
            "$ref": "#/components/responses/Forbidden"
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/v1/admin/products": {
      "get": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Product list (paginated, filterable)",
        "parameters": [
          {
            "$ref": "#/components/parameters/Page"
          },
          {
            "$ref": "#/components/parameters/Limit"
          },
          {
            "$ref": "#/components/parameters/Key"
          },
          {
            "$ref": "#/components/parameters/SortBy"
          },
          {
            "$ref": "#/components/parameters/Order"
          },
          {
            "name": "type",
            "in": "query",
            "description": "Product type id",
            "schema": {
              "type": "string"
            }
          },
          {
            "name": "creator",
            "in": "query",
            "description": "Creator user id",
            "schema": {
              "type": "string"
            }
          },
          {
            "$ref": "#/components/parameters/StartDate"
          },
          {
            "$ref": "#/components/parameters/EndDate"
          }
        ],
        "responses": {
          "200": {
            "description": "Products",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "$ref": "#/components/schemas/Paginated"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "$ref": "#/components/schemas/Product"
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      },
      "post": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Create product",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/ProductInput"
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": "Created",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Product"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "409": {
            "$ref": "#/components/responses/Conflict"
          },
          "422": {
            "$ref": "#/components/responses/InvalidEntity"
          }
        }
      }
    },
    "/api/v1/admin/products/{id}": {
      "get": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Product detail",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Product",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Product"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "put": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Update product (all fields optional)",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "$ref": "#/components/schemas/ProductInput"
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Updated",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Product"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "delete": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Delete product",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/v1/admin/products/low-stock": {
      "get": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Products at or below their stock warning line",
        "parameters": [
          {
            "$ref": "#/components/parameters/Limit"
          }
        ],
        "responses": {
          "200": {
            "description": "Low-stock products, emptiest first",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "object",
                          "properties": {
                            "products": {
                              "type": "array",
                              "items": {
                                "$ref": "#/components/schemas/Product"
                              }
                            },
                            "total": {
                              "type": "integer"
                            }
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/v1/admin/products/setup-data": {
      "get": {
        "tags": [
          "Admin / Products"
        ],
        "summary": "Dropdown data for the product form (types, creators)",
        "responses": {
          "200": {
            "description": "Setup data",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          }
        }
      }
    },
    "/api/v1/admin/types": {
      "get": {
        "tags": [
          "Admin / Types"
        ],
        "summary": "Product type list (paginated)",
        "parameters": [
          {
            "$ref": "#/components/parameters/Page"
          },
          {
            "$ref": "#/components/parameters/Limit"
          }
        ],
        "responses": {
          "200": {
            "description": "Types",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "$ref": "#/components/schemas/Paginated"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "$ref": "#/components/schemas/ProductType"
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      },
      "post": {
        "tags": [
          "Admin / Types"
        ],
        "summary": "Create product type",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "name"
                ],
                "properties": {
                  "name": {
                    "type": "string",
                    "example": "Dessert"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": "Created",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/ProductType"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "409": {
            "$ref": "#/components/responses/Conflict"
          },
          "422": {
            "$ref": "#/components/responses/InvalidEntity"
          }
        }
      }
    },
    "/api/v1/admin/types/{id}": {
      "get": {
        "tags": [
          "Admin / Types"
        ],
        "summary": "Product type detail",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Type",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/ProductType"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "put": {
        "tags": [
          "Admin / Types"
        ],
        "summary": "Rename product type",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "name"
                ],
                "properties": {
                  "name": {
                    "type": "string"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "delete": {
        "tags": [
          "Admin / Types"
        ],
        "summary": "Delete product type",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/v1/admin/sales": {
      "get": {
        "tags": [
          "Admin / Sales"
        ],
        "summary": "All sales (paginated, filterable)",
        "parameters": [
          {
            "$ref": "#/components/parameters/Page"
          },
          {
            "$ref": "#/components/parameters/Limit"
          },
          {
            "$ref": "#/components/parameters/Key"
          },
          {
            "$ref": "#/components/parameters/SortBy"
          },
          {
            "$ref": "#/components/parameters/Order"
          },
          {
            "name": "user",
            "in": "query",
            "description": "Cashier user id",
            "schema": {
              "type": "string"
            }
          },
          {
            "$ref": "#/components/parameters/Platform"
          },
          {
            "$ref": "#/components/parameters/StartDate"
          },
          {
            "$ref": "#/components/parameters/EndDate"
          }
        ],
        "responses": {
          "200": {
            "description": "Orders",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "$ref": "#/components/schemas/Paginated"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "$ref": "#/components/schemas/Order"
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    },
    "/api/v1/admin/sales/{id}": {
      "get": {
        "tags": [
          "Admin / Sales"
        ],
        "summary": "Order detail",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Order",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/Order"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "delete": {
        "tags": [
          "Admin / Sales"
        ],
        "summary": "Delete order",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/v1/admin/sales/setup-data": {
      "get": {
        "tags": [
          "Admin / Sales"
        ],
        "summary": "Dropdown data for the sales filter (cashiers)",
        "responses": {
          "200": {
            "description": "Setup data",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          }
        }
      }
    },
    "/api/v1/admin/users": {
      "get": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "User list (paginated)",
        "parameters": [
          {
            "$ref": "#/components/parameters/Page"
          },
          {
            "$ref": "#/components/parameters/Limit"
          },
          {
            "$ref": "#/components/parameters/Key"
          }
        ],
        "responses": {
          "200": {
            "description": "Users",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "$ref": "#/components/schemas/Paginated"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "type": "array",
                          "items": {
                            "$ref": "#/components/schemas/User"
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      },
      "post": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "Create user",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "name",
                  "phone",
                  "email",
                  "password",
                  "roles"
                ],
                "properties": {
                  "name": {
                    "type": "string"
                  },
                  "phone": {
                    "type": "string"
                  },
                  "email": {
                    "type": "string",
                    "format": "email"
                  },
                  "password": {
                    "type": "string",
                    "format": "password"
                  },
                  "roles": {
                    "type": "array",
                    "items": {
                      "type": "integer",
                      "enum": [
                        1,
                        2
                      ]
                    },
                    "example": [
                      2
                    ]
                  }
                }
              }
            }
          }
        },
        "responses": {
          "201": {
            "description": "Created",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/User"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "409": {
            "$ref": "#/components/responses/Conflict"
          },
          "422": {
            "$ref": "#/components/responses/InvalidEntity"
          }
        }
      }
    },
    "/api/v1/admin/users/{id}": {
      "get": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "User detail",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "User",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/User"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "put": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "Update user (name / phone / email / roles)",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "properties": {
                  "name": {
                    "type": "string"
                  },
                  "phone": {
                    "type": "string"
                  },
                  "email": {
                    "type": "string"
                  },
                  "roles": {
                    "type": "array",
                    "items": {
                      "type": "integer",
                      "enum": [
                        1,
                        2
                      ]
                    }
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Updated",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/User"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      },
      "delete": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "Delete user",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/v1/admin/users/{id}/status": {
      "put": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "Enable or disable a user",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "is_active"
                ],
                "properties": {
                  "is_active": {
                    "type": "boolean"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Updated user",
            "content": {
              "application/json": {
                "schema": {
                  "allOf": [
                    {
                      "$ref": "#/components/schemas/SuccessEnvelope"
                    },
                    {
                      "type": "object",
                      "properties": {
                        "data": {
                          "$ref": "#/components/schemas/User"
                        }
                      }
                    }
                  ]
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/v1/admin/users/{id}/password": {
      "put": {
        "tags": [
          "Admin / Users"
        ],
        "summary": "Reset a user's password",
        "parameters": [
          {
            "$ref": "#/components/parameters/IdPath"
          }
        ],
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "password"
                ],
                "properties": {
                  "password": {
                    "type": "string",
                    "format": "password"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Success with no payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          },
          "404": {
            "$ref": "#/components/responses/NotFound"
          }
        }
      }
    },
    "/api/v1/admin/dashboard": {
      "get": {
        "tags": [
          "Admin / Dashboard"
        ],
        "summary": "Dashboard aggregates (today's orders, revenue, top products)",
        "responses": {
          "200": {
            "description": "Dashboard payload",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          }
        }
      }
    },
    "/api/v1/testing/basic": {
      "get": {
        "tags": [
          "Testing"
        ],
        "security": [],
        "summary": "Unauthenticated echo endpoint",
        "responses": {
          "200": {
            "description": "Echo",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          }
        }
      }
    },
    "/api/v1/testing/upload/file": {
      "post": {
        "tags": [
          "Testing"
        ],
        "security": [],
        "summary": "Proxy a base64 image to the file service",
        "requestBody": {
          "required": true,
          "content": {
            "application/json": {
              "schema": {
                "type": "object",
                "required": [
                  "image"
                ],
                "properties": {
                  "image": {
                    "type": "string",
                    "description": "data-URL base64 image"
                  },
                  "folder": {
                    "type": "string",
                    "default": "test"
                  }
                }
              }
            }
          }
        },
        "responses": {
          "200": {
            "description": "File service response (contains uri)",
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/SuccessEnvelope"
                }
              }
            }
          }
        }
      }
    },
    "/openapi": {
      "get": {
        "tags": [
          "Health"
        ],
        "security": [],
        "summary": "This OpenAPI document (JSON)",
        "responses": {
          "200": {
            "description": "OpenAPI 3.0.3 spec",
            "content": {
              "application/json": {
                "schema": {
                  "type": "object"
                }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "securitySchemes": {
      "bearerAuth": {
        "type": "http",
        "scheme": "bearer",
        "bearerFormat": "JWT"
      }
    },
    "parameters": {
      "IdPath": {
        "name": "id",
        "in": "path",
        "required": true,
        "description": "Mongo ObjectId hex string",
        "schema": {
          "type": "string",
          "example": "64f1a0000000000000000001"
        }
      },
      "TranIdPath": {
        "name": "tranId",
        "in": "path",
        "required": true,
        "description": "Payment transaction id issued by this POS (at most 20 characters)",
        "schema": {
          "type": "string",
          "example": "2603121000001"
        }
      },
      "Page": {
        "name": "page",
        "in": "query",
        "schema": {
          "type": "integer",
          "default": 1,
          "minimum": 1
        }
      },
      "Limit": {
        "name": "limit",
        "in": "query",
        "schema": {
          "type": "integer",
          "default": 10,
          "minimum": 1,
          "maximum": 100
        }
      },
      "Key": {
        "name": "key",
        "in": "query",
        "description": "Case-insensitive search keyword",
        "schema": {
          "type": "string"
        }
      },
      "SortBy": {
        "name": "sort_by",
        "in": "query",
        "x-aliases": [
          "sort"
        ],
        "description": "Field to sort by",
        "schema": {
          "type": "string"
        }
      },
      "Order": {
        "name": "order",
        "in": "query",
        "schema": {
          "type": "string",
          "enum": [
            "ASC",
            "DESC"
          ],
          "default": "ASC"
        }
      },
      "Platform": {
        "name": "platform",
        "in": "query",
        "schema": {
          "type": "string",
          "example": "Web"
        }
      },
      "StartDate": {
        "name": "startDate",
        "in": "query",
        "description": "Date range start (DD-MM-YYYY)",
        "schema": {
          "type": "string"
        }
      },
      "EndDate": {
        "name": "endDate",
        "in": "query",
        "description": "Date range end (DD-MM-YYYY)",
        "schema": {
          "type": "string"
        }
      }
    },
    "responses": {
      "BadRequest": {
        "description": "Bad request",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorEnvelope"
            }
          }
        }
      },
      "Unauthorized": {
        "description": "Missing or invalid token / bad credentials",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorEnvelope"
            }
          }
        }
      },
      "Forbidden": {
        "description": "Wrong role for this route",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorEnvelope"
            }
          }
        }
      },
      "NotFound": {
        "description": "Entity not found",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorEnvelope"
            }
          }
        }
      },
      "Conflict": {
        "description": "Duplicate value (unique constraint)",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorEnvelope"
            }
          }
        }
      },
      "InvalidEntity": {
        "description": "Validation failed",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ValidationErrorEnvelope"
            }
          }
        }
      },
      "BadGateway": {
        "description": "PayWay refused the request or answered something unreadable",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorEnvelope"
            }
          }
        }
      },
      "ServiceUnavailable": {
        "description": "A dependency needed for this route is not usable (database down, or payment credentials absent)",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/ErrorEnvelope"
            }
          }
        }
      },
      "SuccessNoData": {
        "description": "Success with no payload",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/SuccessEnvelope"
            }
          }
        }
      },
      "Accepted": {
        "description": "Noted. The gateway's claim is being checked; the outcome is read back from the payment.",
        "content": {
          "application/json": {
            "schema": {
              "$ref": "#/components/schemas/SuccessEnvelope"
            }
          }
        }
      }
    },
    "schemas": {
      "SuccessEnvelope": {
        "type": "object",
        "required": [
          "success",
          "status_code"
        ],
        "properties": {
          "success": {
            "type": "boolean",
            "example": true
          },
          "status_code": {
            "type": "integer",
            "example": 200
          },
          "data": {
            "nullable": true
          },
          "message": {
            "type": "string"
          }
        }
      },
      "ErrorEnvelope": {
        "type": "object",
        "required": [
          "success",
          "status_code",
          "error"
        ],
        "properties": {
          "success": {
            "type": "boolean",
            "example": false
          },
          "status_code": {
            "type": "integer",
            "example": 401
          },
          "error": {
            "type": "string",
            "example": "Token not provided"
          },
          "timestamp": {
            "type": "string",
            "example": "19-09-2026 03:45:12 PM"
          },
          "path": {
            "type": "string",
            "example": "/api/v1/admin/products"
          }
        }
      },
      "ValidationErrorEnvelope": {
        "allOf": [
          {
            "$ref": "#/components/schemas/ErrorEnvelope"
          },
          {
            "type": "object",
            "properties": {
              "errors": {
                "type": "array",
                "items": {
                  "type": "object",
                  "properties": {
                    "type": {
                      "type": "string",
                      "example": "field"
                    },
                    "message": {
                      "type": "string",
                      "example": "name is required"
                    }
                  }
                }
              }
            }
          }
        ]
      },
      "Paginated": {
        "type": "object",
        "properties": {
          "pagination": {
            "type": "object",
            "properties": {
              "page": {
                "type": "integer"
              },
              "limit": {
                "type": "integer"
              },
              "totalPage": {
                "type": "integer"
              },
              "total": {
                "type": "integer"
              }
            }
          }
        }
      },
      "LoginRequest": {
        "type": "object",
        "required": [
          "username",
          "password"
        ],
        "properties": {
          "username": {
            "type": "string",
            "example": "admin@pos.local"
          },
          "password": {
            "type": "string",
            "format": "password",
            "example": "admin123"
          },
          "platform": {
            "type": "string",
            "default": "Web"
          }
        }
      },
      "TokenResponse": {
        "type": "object",
        "properties": {
          "token": {
            "type": "string",
            "description": "JWT (HS256, 24h). Payload embeds the user and its roles; the default role is marked is_default."
          }
        }
      },
      "User": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string"
          },
          "name": {
            "type": "string"
          },
          "phone": {
            "type": "string"
          },
          "email": {
            "type": "string"
          },
          "avatar": {
            "type": "string",
            "nullable": true,
            "description": "Relative file path, e.g. api/file/<uuid>"
          },
          "is_active": {
            "type": "boolean"
          },
          "roles": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "role_id": {
                  "type": "integer",
                  "enum": [
                    1,
                    2
                  ]
                },
                "name": {
                  "type": "string",
                  "enum": [
                    "Admin",
                    "Cashier"
                  ]
                },
                "is_default": {
                  "type": "boolean"
                }
              }
            }
          },
          "created_at": {
            "type": "string",
            "format": "date-time"
          },
          "updated_at": {
            "type": "string",
            "format": "date-time"
          }
        }
      },
      "UserLog": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string"
          },
          "user_id": {
            "type": "string"
          },
          "ip": {
            "type": "string"
          },
          "user_agent": {
            "type": "string"
          },
          "platform": {
            "type": "string"
          },
          "created_at": {
            "type": "string",
            "format": "date-time"
          }
        }
      },
      "ProductType": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string"
          },
          "name": {
            "type": "string"
          },
          "created_at": {
            "type": "string",
            "format": "date-time"
          },
          "updated_at": {
            "type": "string",
            "format": "date-time"
          }
        }
      },
      "ProductInput": {
        "type": "object",
        "required": [
          "name",
          "code",
          "type",
          "unit_price"
        ],
        "properties": {
          "name": {
            "type": "string",
            "example": "Test Burger"
          },
          "code": {
            "type": "string",
            "example": "P0005",
            "description": "Unique product code"
          },
          "type": {
            "type": "string",
            "description": "Product type id"
          },
          "unit_price": {
            "type": "number",
            "minimum": 0,
            "example": 4.5
          },
          "image": {
            "type": "string",
            "nullable": true,
            "description": "data-URL base64 image; forwarded to the file service, stored as api/file/<uuid>"
          },
          "is_active": {
            "type": "boolean",
            "default": true
          },
          "stock": {
            "type": "integer",
            "minimum": 0,
            "nullable": true,
            "description": "Units on hand; omit or null to leave the product untracked"
          },
          "low_stock_threshold": {
            "type": "integer",
            "minimum": 0,
            "nullable": true,
            "description": "Warn at or below this many units; null warns only at zero"
          }
        }
      },
      "Product": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string"
          },
          "name": {
            "type": "string"
          },
          "code": {
            "type": "string"
          },
          "type": {
            "type": "string",
            "description": "Product type id"
          },
          "type_name": {
            "type": "string",
            "nullable": true
          },
          "unit_price": {
            "type": "number"
          },
          "image": {
            "type": "string",
            "nullable": true
          },
          "is_active": {
            "type": "boolean"
          },
          "stock": {
            "type": "integer",
            "nullable": true,
            "description": "Units on hand; null means the product is not stock-tracked"
          },
          "low_stock_threshold": {
            "type": "integer",
            "nullable": true,
            "description": "Warn at or below this many units; null warns only at zero"
          },
          "creator_id": {
            "type": "string"
          },
          "creator_name": {
            "type": "string",
            "nullable": true
          },
          "created_at": {
            "type": "string",
            "format": "date-time"
          },
          "updated_at": {
            "type": "string",
            "format": "date-time"
          }
        }
      },
      "OrderItem": {
        "type": "object",
        "properties": {
          "product_id": {
            "type": "string"
          },
          "name": {
            "type": "string"
          },
          "qty": {
            "type": "integer"
          },
          "unit_price": {
            "type": "number",
            "description": "Price snapshotted at sale time"
          },
          "line_price": {
            "type": "number"
          }
        }
      },
      "Order": {
        "type": "object",
        "properties": {
          "id": {
            "type": "string"
          },
          "receipt_number": {
            "type": "string",
            "description": "Sequential 7-digit receipt number",
            "example": "1000001"
          },
          "cashier_id": {
            "type": "string"
          },
          "cashier_name": {
            "type": "string",
            "nullable": true
          },
          "platform": {
            "type": "string",
            "example": "Web"
          },
          "total_price": {
            "type": "number"
          },
          "items": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/OrderItem"
            }
          },
          "ordered_at": {
            "type": "string",
            "format": "date-time"
          },
          "payment_tran_id": {
            "type": "string",
            "nullable": true,
            "description": "Set when the sale came from a confirmed QR payment; null for a cash sale"
          }
        }
      },
      "Payment": {
        "type": "object",
        "description": "One QR payment. A sale exists only once the status is paid.",
        "properties": {
          "id": {
            "type": "string"
          },
          "tran_id": {
            "type": "string",
            "description": "Id this POS issues to the payment gateway for the transaction",
            "example": "2603121000001"
          },
          "cashier_id": {
            "type": "string"
          },
          "cashier_name": {
            "type": "string",
            "nullable": true
          },
          "platform": {
            "type": "string",
            "example": "Web"
          },
          "status": {
            "type": "string",
            "enum": [
              "pending",
              "scanned",
              "paid",
              "expired",
              "declined",
              "failed"
            ]
          },
          "provider": {
            "type": "string",
            "enum": [
              "payway",
              "cutluy"
            ],
            "description": "Which gateway the code was issued by. Only that gateway settles the payment."
          },
          "amount": {
            "type": "number"
          },
          "currency": {
            "type": "string",
            "enum": [
              "KHR",
              "USD"
            ]
          },
          "charge_amount": {
            "type": "number",
            "description": "What the customer is charged. Equals amount unless the gateway takes a currency the shop does not price in."
          },
          "charge_currency": {
            "type": "string",
            "enum": [
              "KHR",
              "USD"
            ],
            "description": "Currency of charge_amount"
          },
          "exchange_rate": {
            "type": "number",
            "nullable": true,
            "description": "Shop currency per charged unit, recorded when a conversion produced the code. Null when there was none."
          },
          "items": {
            "type": "array",
            "items": {
              "$ref": "#/components/schemas/OrderItem"
            }
          },
          "qr_string": {
            "type": "string",
            "description": "EMVCo payload to render as a QR. Empty once the payment is no longer pending."
          },
          "abapay_deeplink": {
            "type": "string",
            "description": "Opens ABA Mobile instead of scanning (PayWay). Empty once the payment is no longer pending."
          },
          "checkout_url": {
            "type": "string",
            "description": "Hosted checkout page the customer can be sent to instead of scanning. Empty once the payment is no longer pending."
          },
          "app_store_url": {
            "type": "string"
          },
          "play_store_url": {
            "type": "string"
          },
          "created_at": {
            "type": "string",
            "format": "date-time"
          },
          "expires_at": {
            "type": "string",
            "format": "date-time"
          },
          "paid_at": {
            "type": "string",
            "format": "date-time",
            "nullable": true
          },
          "payment_amount": {
            "type": "number",
            "nullable": true,
            "description": "What the payer actually paid, which may differ in currency from the amount"
          },
          "payment_currency": {
            "type": "string",
            "nullable": true
          },
          "error": {
            "type": "string",
            "nullable": true,
            "description": "Why the payment is declined or failed, in the gateway's words"
          },
          "sale_id": {
            "type": "string",
            "nullable": true,
            "description": "The sale this payment created. Null until paid."
          },
          "receipt_number": {
            "type": "string",
            "nullable": true
          }
        }
      },
      "CutLuyEvent": {
        "type": "object",
        "description": "A CutLuy webhook delivery. data.payment.reference_id is this POS's transaction id.",
        "required": [
          "id",
          "type",
          "data"
        ],
        "properties": {
          "id": {
            "type": "string",
            "description": "Delivery id"
          },
          "type": {
            "type": "string",
            "enum": [
              "payment.completed",
              "payment.scanned",
              "payment.expired",
              "payment.failed"
            ]
          },
          "created": {
            "type": "string",
            "format": "date-time"
          },
          "data": {
            "type": "object",
            "properties": {
              "payment": {
                "type": "object",
                "required": [
                  "id",
                  "status"
                ],
                "properties": {
                  "id": {
                    "type": "string",
                    "description": "CutLuy's payment id"
                  },
                  "status": {
                    "type": "string",
                    "enum": [
                      "pending",
                      "scanned",
                      "paid",
                      "expired",
                      "failed"
                    ]
                  },
                  "amount": {
                    "type": "string",
                    "example": "1.50"
                  },
                  "currency": {
                    "type": "string",
                    "example": "USD"
                  },
                  "reference_id": {
                    "type": "string",
                    "description": "Transaction id this POS issued",
                    "example": "2603121000001"
                  },
                  "approved_at": {
                    "type": "string",
                    "format": "date-time",
                    "nullable": true
                  }
                }
              }
            }
          }
        }
      },
      "PaywayNotification": {
        "type": "object",
        "description": "A PayWay notification. It carries no signature, so only tran_id is used — as an address to re-read, never as evidence.",
        "required": [
          "tran_id"
        ],
        "properties": {
          "tran_id": {
            "type": "string",
            "example": "2603121000001"
          },
          "status": {
            "type": "string",
            "description": "The gateway's own code for the outcome. Ignored; the Check-transaction API answers instead."
          },
          "payment_type": {
            "type": "string",
            "description": "Instrument the payer used"
          },
          "payment_amount": {
            "type": "number"
          },
          "payment_currency": {
            "type": "string"
          },
          "bank_ref": {
            "type": "string"
          }
        }
      }
    }
  }
}
''';
