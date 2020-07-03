CREATE OR REPLACE PACKAGE XXVEN_AR_RCPTS_CREDITCARD_PKG AUTHID CURRENT_USER AS
-- +=================================================================+
-- |                 VENANCIO, RIO DE JANEIRO, BRASIL                |
-- |                       ALL RIGHTS RESERVED.                      |
-- +=================================================================+
-- | FILENAME                                                        |
-- |  XXVEN_AR_RCPTS_CREDITCARD_PKG.pks                              |
-- | PURPOSE                                                         |
-- |  Script de criacao de PACKAGE XXVEN_AR_RCPTS_CREDITCARD_PKG     |
-- |                                                                 |
-- | DESCRIPTION                                                     |
-- |   Aplicar Recebimento aos Titulos de Cartao de Credito.         |
-- |   Execução somente pela Equipe de TI                            |
-- |                                                                 |
-- | PARAMETERS                                                      |
-- |                                                                 |
-- | CREATED BY   Alessandro Chaves   - (2020/07/03)                 |
-- | UPDATED BY                                                      |
-- |             <Developer's name> - <Date>                         |
-- |              <Description>                                      |
-- |                                                                 |
-- +=================================================================+
--  
  PROCEDURE MAIN_P 
    (
        errbuf    OUT VARCHAR2
      , retcode   OUT NUMBER
      , p_dt_ini   IN VARCHAR2 DEFAULT NULL
      , p_dt_fin   IN VARCHAR2 DEFAULT NULL
      , p_customer_id  IN  NUMBER   
    )
  ;
  --
  PROCEDURE OUTPUT_P (p_message IN VARCHAR2)
  ;
  --
  PROCEDURE LOG_II_P
    (
       P_CUSTOMER_TRX_ID      IN NUMBER
     , P_CUSTOMER_ID          IN NUMBER
     , P_PAYMENT_SCHEDULE_ID  IN NUMBER
     , P_AMOUNT_DUE_ORIGINAL  IN NUMBER
     , P_DUE_DATE             IN DATE
     , P_GL_DATE              IN DATE
     , P_CUSTOMER_SITE_USE_ID IN NUMBER
     , P_TRX_DATE             IN DATE
     , P_DESCRICAO            IN VARCHAR2
    )
  ;
  --
  PROCEDURE APPLY_RECEIPT_P
    (  errbuf   OUT VARCHAR2
     , retcode  OUT NUMBER
     , p_customer_id   IN NUMBER
    )
  ;
  --
  PROCEDURE CREATE_INV_ADJ_P
    (
        errbuf    OUT VARCHAR2
      , retcode   OUT NUMBER
    )
  ;
END XXVEN_AR_RCPTS_CREDITCARD_PKG;