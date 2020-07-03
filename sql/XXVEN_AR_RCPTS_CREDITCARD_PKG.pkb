CREATE OR REPLACE PACKAGE bODY XXVEN_AR_RCPTS_CREDITCARD_PKG AS
-- +=================================================================+
-- |                 VENANCIO, RIO DE JANEIRO, BRASIL                |
-- |                       ALL RIGHTS RESERVED.                      |
-- +=================================================================+
-- | FILENAME                                                        |
-- |  XXVEN_AR_RCPTS_CREDITCARD_PKG.pkb                              |
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
        errbuf         OUT VARCHAR2
      , retcode        OUT NUMBER
      , p_dt_ini       IN  VARCHAR2 DEFAULT NULL
      , p_dt_fin       IN  VARCHAR2 DEFAULT NULL
      , p_customer_id  IN  NUMBER   
    )
  IS
    ld_start_date   DATE;
    ld_end_date     DATE;
  BEGIN
    --
    IF p_dt_ini IS NOT NULL THEN ld_start_date := fnd_date.canonical_to_date(p_dt_ini); END IF;
    IF p_dt_fin IS NOT NULL THEN ld_end_date   := fnd_date.canonical_to_date(p_dt_fin); END IF;
	--
	-- Customer_id: 11110 (TEMPO SERVICOS LTDA); 11108 (REDECARD SA); 10109 (CIELO SA)
    --
    APPLY_RECEIPT_P
      (
          errbuf          => errbuf    
        , retcode         => retcode
        , p_customer_id   => p_customer_id

      )
    ;
    CREATE_INV_ADJ_P
      (
          errbuf          => errbuf    
        , retcode         => retcode
      )
    ;
  END main_p;
  --
  PROCEDURE OUTPUT_P (p_message IN VARCHAR2)
  IS
  BEGIN
    fnd_file.put_line (fnd_file.log, p_message);
  END OUTPUT_P;
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
  IS
    PRAGMA AUTONOMOUS_TRANSACTION;
  BEGIN
    INSERT INTO XXVEN_ERRO_ADJ_TB
    VALUES
      (
         p_customer_trx_id
       , p_customer_id
       , p_payment_schedule_id
       , p_amount_due_original
       , p_due_date
       , p_gl_date
       , p_customer_site_use_id
       , p_trx_date
       , p_descricao
       , SYSDATE
	  )
    ;
	COMMIT;
    fnd_file.put_line (fnd_file.log, 'CUSTOMER_TRX_ID = '||P_CUSTOMER_TRX_ID||' PAYMENT_SCHEDULE_ID = '|| P_PAYMENT_SCHEDULE_ID|| ' ERRO: '||P_DESCRICAO);
  END LOG_II_P;
  --
  PROCEDURE APPLY_RECEIPT_P
    (  errbuf          OUT VARCHAR2
     , retcode         OUT NUMBER
     , p_customer_id   IN NUMBER
    )
  IS
    -- COLUMNS --
    -- AR_PAYMENT_SCHEDULES_ALL --
    -- payment_schedule_id
    TYPE payment_schedule_id_t    IS TABLE OF ar_payment_schedules_all.payment_schedule_id%TYPE INDEX BY PLS_INTEGER;
    l_payment_schedule_id         payment_schedule_id_t;
    -- amount_due_remaining
    TYPE amount_due_remaining_t   IS TABLE OF ar_payment_schedules_all.amount_due_remaining%TYPE INDEX BY PLS_INTEGER;
    l_amount_due_remaining        amount_due_remaining_t;
     --AR_CASH_RECEIPTS_ALL --
    -- cash_receipt_id
    TYPE cash_receipt_id_t        IS TABLE OF ar_cash_receipts_all.cash_receipt_id%TYPE INDEX BY PLS_INTEGER;
    l_cash_receipt_id             cash_receipt_id_t;
    -- receipt_number
    TYPE receipt_number_t         IS TABLE OF ar_cash_receipts_all.receipt_number%TYPE INDEX BY PLS_INTEGER;
    l_receipt_number              receipt_number_t;
     --RA_CUSTOMER_TRX_ALL --
    -- customer_trx_id
    TYPE customer_trx_id_t       IS TABLE OF ra_customer_trx_all.customer_trx_id%TYPE INDEX BY PLS_INTEGER;
    l_customer_trx_id            customer_trx_id_t;
    -- trx_date
    TYPE trx_date_t              IS TABLE OF ra_customer_trx_all.trx_date%TYPE INDEX BY PLS_INTEGER;
    l_trx_date                   trx_date_t;
    -- trx_number
    TYPE trx_number_t            IS TABLE OF ra_customer_trx_all.trx_number%TYPE INDEX BY PLS_INTEGER;
    l_trx_number                 trx_number_t;
    TYPE lt_customer_id          IS TABLE OF ar_payment_schedules_all.customer_id%TYPE INDEX BY PLS_INTEGER;
    l_customer_id                lt_customer_id;

    x_return_status                VARCHAR2(400);
    x_msg_count                    NUMBER;
    x_msg_data                     VARCHAR2(400);
    ln_count                       NUMBER;
    ln_count_errornf               NUMBER := 0;
    ln_count_succesnf              NUMBER := 0;
    ln_amount_trx                  NUMBER;
    ln_cash_receipt_id             ar_cash_receipts_all.cash_receipt_id%TYPE;
    ln_user_id                     fnd_user.user_id%TYPE;
    ln_resp_id                     fnd_responsibility_tl.responsibility_id%TYPE;
    ln_resp_appl_id                fnd_responsibility_tl.application_id%TYPE;

    CANNOT_APP_PSTV_AMNT_FRST      EXCEPTION;

	PROCEDURE insert_error
      (
          p_customer_id          IN NUMBER
        , p_customer_trx_id      IN NUMBER
        , p_payment_schedule_id  IN NUMBER
        , p_error_log            IN VARCHAR2
        , p_creation_date        IN DATE
      )
    IS
      PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
      INSERT INTO XXVEN_TMP_LOG_TB
      VALUES
        (
            p_customer_id
          , p_customer_trx_id
          , p_payment_schedule_id
          , p_error_log
          , p_creation_date
        )
      ;
      COMMIT;
    END insert_error;
    -- 

  BEGIN
    EXECUTE IMMEDIATE (' alter session set nls_language  = '||CHR(39)||'AMERICAN'||CHR(39));
    -- Set the applications context
    BEGIN
      mo_global.init('AR');
      mo_global.set_policy_context( p_access_mode => 'S', p_org_id => fnd_global.org_id ); -- 83);
      SELECT
                f.user_id
              , res.responsibility_id
              , res.application_id
        INTO
                ln_user_id
              , ln_resp_id
              , ln_resp_appl_id
        FROM
                fnd_user              f
              , fnd_responsibility_tl res
      WHERE  1=1
        AND f.user_name             = 'SYSADMIN'
        AND res.responsibility_name = 'DV AR SUPER USUARIO'
        AND res.language            = 'PTB'
      ;
      fnd_global.APPS_INITIALIZE
        (   user_id      => ln_user_id
          , resp_id      => ln_resp_id
          , resp_appl_id => ln_resp_appl_id
        )
      ;
    END;
    --
    fnd_file.put_line(fnd_file.log,'-------------------------------------------------------------------------------');
    fnd_file.put_line(fnd_file.log,'    Inicio APPLY_RECEIPT_P  ');

    BEGIN
      SELECT
               rcta.customer_trx_id
             , apsa.payment_schedule_id
             , apsa.amount_due_remaining
             , rcta.trx_date
             , rcta.trx_number
             , apsa.customer_id
        BULK COLLECT INTO
                 l_customer_trx_id
               , l_payment_schedule_id
               , l_amount_due_remaining
               , l_trx_date
               , l_trx_number
			   , l_customer_id
        FROM
               ra_customer_trx_all           rcta
             , ar_payment_schedules_all      apsa
             , ra_cust_trx_types_all         rctta
      WHERE 1=1
        AND rctta.cust_trx_type_id        = rcta.cust_trx_type_id
        AND apsa.customer_trx_id          = rcta.customer_trx_id
        AND rctta.name                    IN ( '5102_5405_ANALISA', '5102_5405_VENDA_MERC', 'CARTAO DE CRÉDITO', 'NOTA DE DÉBITO' )
        AND rcta.trx_date                 <= TO_DATE( '30/09/2019', 'DD/MM/YYYY' )
        AND rcta.status_trx               != 'VD'
        AND apsa.amount_due_remaining     != '0' 
        AND apsa.status                   != 'CL'
        AND apsa.customer_id              = p_customer_id
        AND NOT EXISTS
          (
            SELECT term_id, name
              FROM ra_terms rtn
            WHERE 1=1
              AND rtn.term_id                 = apsa.term_id
              AND term_id IN 
              (1002,1003,1004,1005,1006,1007,1008,1009,1010,1011,1012,10121,1013,1014,1015,1016,1017,1018,1019,1020,1021,1024,
               1022,1023,1026,1027,16122,18122,19122,20122,2023,2024,2025,2026,2027,2028,2029,2030,2031,2032,2033,2034,2035,2036,2037,2038,2039,2040,2041,2042,2043,2044,2045,22122,25122,25123,26122,26123,27122,
               28122,28123,28124,29122,29123,30122,31122,32122,33122,34122,35122,36122,4116,4117,4118,4119,6121,6122,6123,
               6124,6125,6126,6127,6128,6129,6130,6131,6132,6133,6134,6135,6136,6137,6138,6139,6140,6141,6142,6143,6144,6145,6146,6147,6148,6149,6150,6151,6152,6153,6154,7121,8121,8122,9121,9122
              )
          )
        -- AND rcta.customer_trx_id IN ( 22503506, 22503508, 29516969, 22860534, 29516330, 22187344, 22187434, 22187484, 22190594 )
      ORDER BY rcta.customer_trx_id
      ;
      --
      fnd_file.put_line(fnd_file.log, CHR(13)||'TOTAL DE REGISTROS: '||l_payment_schedule_id.COUNT);

      FOR i IN 1 .. l_payment_schedule_id.COUNT LOOP
        BEGIN
          SELECT acrv.cash_receipt_id
            INTO ln_cash_receipt_id
            FROM  
                   ar_cash_receipts_all  acra
                 , ar_cash_receipts_v    acrv
          WHERE 1=1
            AND acrv.cash_receipt_id                         = acra.cash_receipt_id
            AND acrv.customer_name                           IN ( 'CIELO SA', 'TEMPO SERVICOS LTDA', 'REDECARD SA' )
            AND acra.type                                    = 'CASH'
            AND acra.status                                  NOT IN ('APP','REV','NSF')
            AND acra.RECEIPT_METHOD_ID                       IN (8019,2005,2097,2123,2124,2125,2126,2133,2140,2157,2163,18022,23022)
            AND acra.receipt_date                            <= TO_DATE( '30/09/2019', 'DD/MM/YYYY' )
            AND acrv.customer_id                             =  l_customer_id(i)
            AND ( acrv.net_amount - acrv.applied_amount )    >= l_amount_due_remaining(i)
            AND ROWNUM                                       = 1
          ;

          fnd_file.put_line(fnd_file.log, 'Call AR_RECEIPT_API_PUB.APPLY for CUSTOMER_TRX_ID: ' || l_customer_trx_id(i));
          fnd_file.put_line(fnd_file.log, 'trx_number: '||l_trx_number(i));
          -- passo 4
          -- api para aplicacao
          ar_receipt_api_pub.apply(  p_api_version                 => 1.0
                                   , p_init_msg_list               => fnd_api.g_true
                                   , p_commit                      => fnd_api.g_true
                                   , p_validation_level            => fnd_api.g_valid_level_none
                                   , p_receipt_number              => NULL --l_receipt_number(i)
                                   , p_cash_receipt_id             => ln_cash_receipt_id
                                   , p_customer_trx_id             => l_customer_trx_id(i)
                                   , p_applied_payment_schedule_id => l_payment_schedule_id(i)
                                   , p_amount_applied              => l_amount_due_remaining(i)
                                   , p_apply_date                  => SYSDATE
                                   , p_apply_gl_date               => SYSDATE
                                   , x_return_status               => x_return_status
                                   , x_msg_count                   => x_msg_count
                                   , x_msg_data                    => x_msg_data
                                  );

          IF x_return_status = 'E' THEN
	  	    ROLLBACK;
            IF x_msg_count = 1 THEN


                insert_error
                  (
                      p_customer_id          => l_customer_id(i)
                    , p_customer_trx_id      => l_customer_trx_id(i)
                    , p_payment_schedule_id  => l_payment_schedule_id(i)
                    , p_error_log            => 'Return messages for AR_RECEIPT_API_PUB.APPLY: ' ||x_msg_data
                    , p_creation_date        => SYSDATE
                  )
                ;
                xxven_int_common_services_pk.put_log('Return message for AR_RECEIPT_API_PUB.APPLY: ' || x_msg_data);


            ELSIF x_msg_count > 1 THEN
              LOOP
                ln_count   := ln_count + 1;
                x_msg_data := fnd_msg_pub.get(fnd_msg_pub.g_next, fnd_api.g_false);
                IF x_msg_data IS NULL THEN
                  EXIT;
                END IF;

                  insert_error
                    (
                        p_customer_id          => l_customer_id(i)
                      , p_customer_trx_id      => l_customer_trx_id(i)
                      , p_payment_schedule_id  => l_payment_schedule_id(i)
                      , p_error_log            => 'Return messages for AR_RECEIPT_API_PUB.APPLY: ' ||ln_count || '.' ||x_msg_data
                      , p_creation_date        => SYSDATE
                    )
                  ;
                  xxven_int_common_services_pk.put_log('Return messages for AR_RECEIPT_API_PUB.APPLY: ' ||ln_count || '.' ||x_msg_data);


              END LOOP;
            END IF;

            ln_count_errornf := ln_count_errornf + 1;

            UPDATE ra_customer_trx_all
            SET    attribute3          = 'AR_RECEIPT_API_PUB.APPLY - ERROR'
            WHERE  customer_trx_id     = l_customer_trx_id(i);
            COMMIT;
          ELSE
            ln_amount_trx := ln_amount_trx + l_amount_due_remaining(i);

            UPDATE ra_customer_trx_all
            SET    attribute3          = 'AR_RECEIPT_API_PUB.APPLY - SUCCESSFUL'
            WHERE  customer_trx_id     = l_customer_trx_id(i);
            COMMIT;

            ln_count_succesnf := ln_count_succesnf + 1;

          END IF;

        EXCEPTION
          WHEN NO_DATA_FOUND THEN
            ROLLBACK;
            ln_count_errornf := ln_count_errornf + 1;
            ln_amount_trx    := ln_amount_trx - l_amount_due_remaining(i);

            UPDATE ra_customer_trx_all
            SET    attribute3          = 'AR_RECEIPT_API_PUB.APPLY - ERROR'
            WHERE  customer_trx_id     = l_customer_trx_id(i);

            fnd_file.put_line( fnd_file.log, 'Error: No Data Found Getting Receipt' );
            fnd_file.put_line( fnd_file.log, 'Customer ID.............:  ' || l_customer_id(i) );
            fnd_file.put_line( fnd_file.log, 'Trx ID..................:  ' || l_customer_trx_id(i) );
            fnd_file.put_line( fnd_file.log, 'Amount Remaining........:  ' || l_customer_trx_id(i) );
            fnd_file.put_line( fnd_file.log, 'Error Description.......:  ' || SQLERRM );
            fnd_file.put_line( fnd_file.log, 'ERROR TIME..............:  ' || TO_CHAR( SYSDATE, 'DD/MM/RR HH24:MI' ) );

          WHEN OTHERS THEN
            ROLLBACK;
            ln_count_errornf := ln_count_errornf + 1;
            ln_amount_trx    := ln_amount_trx - l_amount_due_remaining(i);

            UPDATE ra_customer_trx_all
            SET    attribute3          = 'AR_RECEIPT_API_PUB.APPLY - ERROR'
            WHERE  customer_trx_id     = l_customer_trx_id(i);

            fnd_file.put_line(fnd_file.log, 'Error Procedure APPLY_RECEIPT_P');
            fnd_file.put_line(fnd_file.log, 'ID Nota.................:  ' || l_customer_trx_id(i));
            fnd_file.put_line(fnd_file.log, 'Error Description.......   ' || SQLERRM);
            FND_FILE.PUT_LINE(FND_FILE.LOG, 'ERROR TIME..............   ' || TO_CHAR(SYSDATE, 'DD/MM/RR HH24:MI'));

            COMMIT;
        END;
      END LOOP;
      --
    EXCEPTION
      WHEN OTHERS THEN
        fnd_file.put_line(fnd_file.log, CHR(13)||'Nenhum Recebimento foi Localizado!!');
    END;
    --
    fnd_file.put_line(fnd_file.log,CHR(13)||' PROCESSADOS COM ERRO:    '|| ln_count_errornf);
    fnd_file.put_line(fnd_file.log,CHR(13)||' PROCESSADOS COM SUCESSO: '|| ln_count_succesnf);

    fnd_file.put_line(fnd_file.log,CHR(13)||'    Fim APPLY_RECEIPT_P  ');
    fnd_file.put_line(fnd_file.log,'-------------------------------------------------------------------------------');
  END  APPLY_RECEIPT_P;
  --
  PROCEDURE CREATE_INV_ADJ_P
    (
        errbuf    OUT VARCHAR2
      , retcode   OUT NUMBER
    )
  IS
    -- Ajuste 1 --
    CURSOR c_rcta IS -- (p_start_date  DATE, p_end_date  DATE) IS
      SELECT
               apsa.customer_trx_id
             , apsa.customer_id
             , apsa.payment_schedule_id
             , ( apsa.amount_due_original * -1 )   amount_due_original
             , apsa.amount_due_remaining
             , apsa.due_date
             , TO_DATE( '01/07/2020', 'DD/MM/RRRR' )  gl_date
             , apsa.customer_site_use_id
             , rcta.trx_date
        FROM
               ra_customer_trx_all        rcta
             , ar_payment_schedules_all   apsa
	  WHERE 1=1
        AND apsa.customer_trx_id          = rcta.customer_trx_id
        AND EXISTS
           (
             SELECT                      
                      1 --b.payment_schedule_id, A.CUSTOMER_TRX_ID, A.TRX_NUMBER, A.trx_date ,B.DUE_DATE, B.TERMS_SEQUENCE_NUMBER, B.AMOUNT_DUE_ORIGINAL as Valor_Bruto, B.AMOUNT_DUE_REMAINING  as Saldo, a.creation_date
               FROM
                      ra_customer_trx_all      a
                    , ar_payment_schedules_all b
                    , ra_terms                 d
             WHERE 1=1
               AND b.payment_schedule_id      = apsa.payment_schedule_id
               AND a.customer_trx_id          = rcta.customer_trx_id
               AND a.customer_trx_id          = b.customer_trx_id
               AND a.term_id                  = d.term_id
               AND a.bill_to_customer_id      NOT IN (11110, 10109, 11108)
               AND a.org_id                   = fnd_global.org_id            --101 para HN_AJUSTE_BAIXA_CC    AND A.ORG_ID = 83 para DV_AJUSTE_BAIXA_CC
               AND a.trx_date                 <= TO_DATE('30/09/2019','DD/MM/YYYY')
               AND b.amount_due_remaining     <> 0
               AND a.status_trx               != 'VD'
               AND b.status                   != 'CL'
               AND (D.name like '%TPOS_%' OR 
                    D.name like '%TEF%' OR 
                    D.name like '%EQ%')
               AND NOT EXISTS ( SELECT 1 FROM ra_customer_trx_all
                                WHERE 1=1
                                  AND previous_customer_trx_id = a.customer_trx_id
                              )
           )
        -- AND rcta.customer_trx_id IN
    ;    --
	--
    -- Types --
    --
    TYPE lt_customer_trx_id         IS TABLE OF ar_payment_schedules_all.customer_trx_id%TYPE INDEX BY PLS_INTEGER;
    l_customer_trx_id               lt_customer_trx_id;
    TYPE lt_customer_id             IS TABLE OF ar_payment_schedules_all.customer_id%TYPE INDEX BY PLS_INTEGER;
    l_customer_id                   lt_customer_id;
    TYPE lt_payment_schedule_id     IS TABLE OF ar_payment_schedules_all.payment_schedule_id%TYPE INDEX BY PLS_INTEGER;
    l_payment_schedule_id           lt_payment_schedule_id;
    TYPE lt_amount_due_original     IS TABLE OF ar_payment_schedules_all.amount_due_original%TYPE INDEX BY PLS_INTEGER;
    l_amount_due_original           lt_amount_due_original;
    l_amount_due_remaining          lt_amount_due_original;
    TYPE lt_due_date                IS TABLE OF ar_payment_schedules_all.due_date%TYPE INDEX BY PLS_INTEGER;
    l_due_date                      lt_due_date;
    l_trx_date                      lt_due_date;
    TYPE lt_gl_date                 IS TABLE OF ar_payment_schedules_all.gl_date%TYPE INDEX BY PLS_INTEGER;
    l_gl_date                       lt_gl_date;
    TYPE lt_customer_site_use_id    IS TABLE OF ar_payment_schedules_all.customer_site_use_id%TYPE INDEX BY PLS_INTEGER;
    l_customer_site_use_id          lt_customer_site_use_id; 
    --
    -- Local Variables --
    --
    ln_resp_id                      NUMBER := fnd_global.resp_id;
    ln_conc_request_id              NUMBER := fnd_global.conc_request_id;
    ln_user_id                      NUMBER := fnd_global.user_id;
    ln_login_id                     NUMBER := fnd_global.login_id;
    ln_conc_program_id              NUMBER := fnd_global.conc_program_id;
    ln_conc_login_id                NUMBER := fnd_global.conc_login_id;
    ln_prog_appl_id                 NUMBER := fnd_global.prog_appl_id;

    lv_ret_sts_success              VARCHAR2(1):= fnd_api.g_ret_sts_success;
    lv_ret_sts_error                VARCHAR2(1):= fnd_api.g_ret_sts_unexp_error;
    lv_ret_sts_unexp_error          VARCHAR2(1):= fnd_api.g_ret_sts_unexp_error;
    lv_count                        VARCHAR2(1):='0';

    lv_debug                        VARCHAR2(32000);
    lv_error_msg                    VARCHAR2(32000);
    lv_pkname                       VARCHAR2(32000) := 'XXVEN_AR_RODASCRIPT_PK';
    lv_routine                      VARCHAR2(32000) := 'CREATE_INV_ADJ_P';
    lv_msg_data                     VARCHAR2(32000);
    lv_return_status                VARCHAR2(32000) := fnd_api.g_ret_sts_success;
    lv_sucs_msg                     VARCHAR2(32000);
    lv_adjust_type                  VARCHAR2(32000);

    ln_limit                        PLS_INTEGER := 5000;
    ln_cnt                          PLS_INTEGER := 0;
    ln_retcode                      PLS_INTEGER := 0;
    ln_counter                      PLS_INTEGER := 0;
    ln_msg_count                    PLS_INTEGER;
    ln_time                         NUMBER;
    ln_org_id                       NUMBER := fnd_global.org_id;

    l_adjust                        ar_adjustments%ROWTYPE;
    lv_new_adjustment_number        ar_adjustments.adjustment_number%TYPE;
    ln_new_adjustment_id            ar_adjustments.adjustment_id %TYPE;
    ln_receivables_trx_id           ar_receivables_trx_all.receivables_trx_id%TYPE;
    lv_reason_code                  fnd_lookup_values_vl.lookup_code%TYPE;
    lv_organization_code            org_organization_definitions.organization_code%TYPE;
    ln_warehouse_id                 ra_customer_trx_lines_all.warehouse_id%TYPE;

    -- AJUSTE TROCA V  
    FUNCTION GET_RECEIVABLE_TRX_ID
        (
            p_organization_code   IN  VARCHAR2 DEFAULT NULL
        )
    RETURN NUMBER
    IS
      lv_query                VARCHAR2(32000);
      l_crs                   SYS_REFCURSOR;
      ln_receivables_trx_id   ar_receivables_trx_all.receivables_trx_id%TYPE;
      lv_condition            ar_receivables_trx_all.name%TYPE;
    BEGIN

  	lv_condition := 'AJUSTE TROCA V'||p_organization_code;

      lv_query := 'SELECT arta.receivables_trx_id
                     FROM ar_receivables_trx_all  arta
                   WHERE 1=1
                     AND name = :condition
                  '
      ;
      OPEN l_crs FOR lv_query USING lv_condition;
      FETCH l_crs INTO ln_receivables_trx_id;

      RETURN ln_receivables_trx_id;
    EXCEPTION
      WHEN OTHERS THEN
        ln_receivables_trx_id := -1;
    END GET_RECEIVABLE_TRX_ID;
    --
	-- DV_AJUSTE_BAIXA_CC / HN_AJUSTE_BAIXA_CC
    FUNCTION GET_RECEIVABLE_TRX
        (
            p_org_id   IN  NUMBER DEFAULT NULL
        )
    RETURN NUMBER
    IS
      lv_query                VARCHAR2(32000);
      l_crs                   SYS_REFCURSOR;
      ln_receivables_trx_id   ar_receivables_trx_all.receivables_trx_id%TYPE;
      lv_condition            ar_receivables_trx_all.name%TYPE;
    BEGIN

  	  IF p_org_id = 83 THEN
	    lv_condition := 'DV_AJUSTE_BAIXA_CC';
      ELSE
        lv_condition := 'HN_AJUSTE_BAIXA_CC';
      END IF;

      lv_query := 'SELECT arta.receivables_trx_id
                     FROM ar_receivables_trx_all  arta
                   WHERE 1=1
                     AND name = :condition
                  '
      ;
      OPEN l_crs FOR lv_query USING lv_condition;
      FETCH l_crs INTO ln_receivables_trx_id;

      RETURN ln_receivables_trx_id;
    EXCEPTION
      WHEN OTHERS THEN
        ln_receivables_trx_id := -1;
    END GET_RECEIVABLE_TRX;
    --
  BEGIN
    mo_global.init('AR');
    mo_global.set_policy_context( p_access_mode => 'S', p_org_id => fnd_global.org_id ); -- 83);
    fnd_file.put_line (fnd_file.log, lv_routine||' - Início...');

    lv_debug := '(00) - '||lv_pkname||'.'||lv_routine||CHR(13);
    --
    ln_time := dbms_utility.get_time;
    OPEN c_rcta ;
      LOOP
       FETCH c_rcta 
         BULK COLLECT INTO
             l_customer_trx_id
           , l_customer_id
           , l_payment_schedule_id
           , l_amount_due_original
           , l_amount_due_remaining
           , l_due_date
           , l_gl_date
           , l_customer_site_use_id
           , l_trx_date
       LIMIT ln_limit
       ;
       ln_counter := l_customer_trx_id.FIRST;
       WHILE ln_counter IS NOT NULL LOOP
         ln_cnt := ln_cnt + 1;
         SAVEPOINT INICIO;
         --
         -- Get WAREHOUSE_ID --
         lv_debug := '(01) - '||lv_pkname||'.'||lv_routine||CHR(13);
         BEGIN
           SELECT   DISTINCT
                    rctla.warehouse_id
             INTO   ln_warehouse_id
             FROM   ra_customer_trx_lines_all   rctla
           WHERE 1=1
             AND rctla.warehouse_id    IS NOT NULL
             AND rctla.customer_trx_id = l_customer_trx_id(ln_counter)
           ;
         EXCEPTION
           WHEN OTHERS THEN
             retcode := 1;
             LOG_II_P
                 (
                    P_CUSTOMER_TRX_ID      => l_customer_trx_id(ln_counter)
                  , P_CUSTOMER_ID          => l_customer_id(ln_counter)
                  , P_PAYMENT_SCHEDULE_ID  => l_payment_schedule_id(ln_counter)
                  , P_AMOUNT_DUE_ORIGINAL  => l_amount_due_original(ln_counter)
                  , P_DUE_DATE             => l_due_date(ln_counter)
                  , P_GL_DATE              => l_gl_date(ln_counter)
                  , P_CUSTOMER_SITE_USE_ID => l_customer_site_use_id(ln_counter)
                  , P_TRX_DATE             => l_trx_date(ln_counter)
                  , P_DESCRICAO            => lv_debug ||' Erro ao localizar o WAREHOUSE_ID. '||SQLERRM
                 )
             ;
             GOTO PROXIMO;		   
         END;
         --
         -- Get receivables_trx_id --
         lv_debug := '(02) - '||lv_pkname||'.'||lv_routine||CHR(13);
         BEGIN
           SELECT   ood.organization_code
             INTO   lv_organization_code
             FROM
                    cll_f189_fiscal_entities_all rfe
                  , hr_locations                 hl
                  , mtl_parameters               ood -- org_organization_defINitions ood
           WHERE 1=1 
             AND rfe.entity_type_lookup_code  = 'LOCATION'
             AND rfe.inactive_date            IS NULL
             AND hl.location_id               = rfe.location_id
             AND hl.inventory_organization_id = ood.organization_id
             AND ood.organization_id          = ood.organization_id
             AND ood.organization_id          = ln_warehouse_id
           ;
           ln_receivables_trx_id := get_receivable_trx( p_org_id => ln_org_id);
         EXCEPTION
           WHEN OTHERS THEN
             retcode := 1;
             LOG_II_P
                 (
                    P_CUSTOMER_TRX_ID      => l_customer_trx_id(ln_counter)
                  , P_CUSTOMER_ID          => l_customer_id(ln_counter)
                  , P_PAYMENT_SCHEDULE_ID  => l_payment_schedule_id(ln_counter)
                  , P_AMOUNT_DUE_ORIGINAL  => l_amount_due_original(ln_counter)
                  , P_DUE_DATE             => l_due_date(ln_counter)
                  , P_GL_DATE              => l_gl_date(ln_counter)
                  , P_CUSTOMER_SITE_USE_ID => l_customer_site_use_id(ln_counter)
                  , P_TRX_DATE             => l_trx_date(ln_counter)
                  , P_DESCRICAO            => lv_debug ||'  Erro ao localizar RECEIVABLES_TRX_ID - '||SQLERRM
                 )
             ;
             GOTO PROXIMO;		   
         END;
         --
         IF ln_receivables_trx_id IS NULL OR ln_receivables_trx_id = -1 THEN
           retcode := 1;
             LOG_II_P
                 (
                    P_CUSTOMER_TRX_ID      => l_customer_trx_id(ln_counter)
                  , P_CUSTOMER_ID          => l_customer_id(ln_counter)
                  , P_PAYMENT_SCHEDULE_ID  => l_payment_schedule_id(ln_counter)
                  , P_AMOUNT_DUE_ORIGINAL  => l_amount_due_original(ln_counter)
                  , P_DUE_DATE             => l_due_date(ln_counter)
                  , P_GL_DATE              => l_gl_date(ln_counter)
                  , P_CUSTOMER_SITE_USE_ID => l_customer_site_use_id(ln_counter)
                  , P_TRX_DATE             => l_trx_date(ln_counter)
                  , P_DESCRICAO            => lv_debug ||'  **** RECEIVABLES_TRX_ID NULO !! **** '
                 )
             ;
           dbms_output.put_line(lv_error_msg);
           fnd_file.put_line (fnd_file.log, lv_error_msg);
           GOTO PROXIMO;		   
         END IF;
         -- Get Reason Code --
         lv_debug := '(03) - '||lv_pkname||'.'||lv_routine||chr(13);
         BEGIN
           SELECT   lookup_code
             INTO   lv_reason_code
             FROM   fnd_lookup_values_vl
           WHERE 1=1
             AND lookup_type = 'ADJUST_REASON'
             AND lookup_code = 'CANCEL_CRED'
           ;
         EXCEPTION
           WHEN OTHERS THEN
             retcode := 1;
             LOG_II_P
                 (
                    P_CUSTOMER_TRX_ID      => l_customer_trx_id(ln_counter)
                  , P_CUSTOMER_ID          => l_customer_id(ln_counter)
                  , P_PAYMENT_SCHEDULE_ID  => l_payment_schedule_id(ln_counter)
                  , P_AMOUNT_DUE_ORIGINAL  => l_amount_due_original(ln_counter)
                  , P_DUE_DATE             => l_due_date(ln_counter)
                  , P_GL_DATE              => l_gl_date(ln_counter)
                  , P_CUSTOMER_SITE_USE_ID => l_customer_site_use_id(ln_counter)
                  , P_TRX_DATE             => l_trx_date(ln_counter)
                  , P_DESCRICAO            => lv_debug ||'  Erro ao localizar REASON_CODE - '||SQLERRM
                 )
             ;
             GOTO PROXIMO;		   
         END;
         --
         lv_debug := '(04) - '||lv_pkname||'.'||lv_routine||chr(13);
         --
         l_adjust.created_by          := 0; -- ln_user_id;
         l_adjust.creation_date       := SYSDATE;
         l_adjust.last_updated_by     := 0; -- ln_user_id;
         l_adjust.approved_by         := 0; -- ln_user_id;
         l_adjust.last_update_date    := SYSDATE;
         l_adjust.request_id          := ln_conc_request_id;
		 l_adjust.apply_date          := l_gl_date(ln_counter); -- SYSDATE; 
		 l_adjust.gl_date             := l_gl_date(ln_counter);
         l_adjust.comments            := NULL;
         l_adjust.adjustment_type     := 'M';
         l_adjust.status              := 'A';
         l_adjust.customer_trx_id     := l_customer_trx_id(ln_counter);
         l_adjust.payment_schedule_id := l_payment_schedule_id(ln_counter);
         l_adjust.receivables_trx_id  := ln_receivables_trx_id;
         l_adjust.reason_code         := lv_reason_code;
         l_adjust.created_from        := lv_routine;
         l_adjust.postable            := 'Y';
         l_adjust.postINg_control_id  := -3;
         --
		 IF ( l_amount_due_original(ln_counter) * -1 ) = l_amount_due_remaining(ln_counter) THEN
           l_adjust.type                := 'INVOICE';
         ELSIF ( l_amount_due_original(ln_counter) * -1 ) <> l_amount_due_remaining(ln_counter) THEN
           l_adjust.type                := 'LINE';	 
         END IF;
         -- 
         l_adjust.amount              := l_amount_due_original(ln_counter);
         l_adjust.acctd_amount        := l_amount_due_original(ln_counter);
         --
         -- Create Adjustment --
         lv_debug := '(05) - '||lv_pkname||'.'||lv_routine||chr(13);
         BEGIN
           ar_adjust_pub.create_adjustment
             (
                 p_api_name          => 'AR_ADJUST_PUB'          --IN
               , p_api_version       => 1.0                      --IN
               , p_msg_count         => ln_msg_count             --out
               , p_msg_data          => lv_msg_data              --out
               , p_return_status     => lv_return_status         --out
               , p_adj_rec           => l_adjust                 --IN
               , p_new_adjust_number => lv_new_adjustment_number --out
               , p_new_adjust_id     => ln_new_adjustment_id     --out
             )
           ;
           --
           lv_debug := '(05.1) - '||lv_pkname||'.'||lv_routine||chr(13);
           IF lv_return_status <> fnd_api.g_ret_sts_success THEN
             retcode := 1;
             LOG_II_P
                 (
                    P_CUSTOMER_TRX_ID      => l_customer_trx_id(ln_counter)
                  , P_CUSTOMER_ID          => l_customer_id(ln_counter)
                  , P_PAYMENT_SCHEDULE_ID  => l_payment_schedule_id(ln_counter)
                  , P_AMOUNT_DUE_ORIGINAL  => l_amount_due_original(ln_counter)
                  , P_DUE_DATE             => l_due_date(ln_counter)
                  , P_GL_DATE              => l_gl_date(ln_counter)
                  , P_CUSTOMER_SITE_USE_ID => l_customer_site_use_id(ln_counter)
                  , P_TRX_DATE             => l_trx_date(ln_counter)
                  , P_DESCRICAO            => lv_debug ||'  Erro ao criar o Ajuste - '||SQLERRM
                 )
             ;
             IF ln_msg_count > 0 THEN
               FOR i IN 1 .. ln_msg_count LOOP
                 lv_msg_data := fnd_msg_pub.GET(p_msg_index => i, p_encoded => 'F');
                 IF lv_msg_data IS NOT NULL THEN
                   LOG_II_P
                       (
                          P_CUSTOMER_TRX_ID      => l_customer_trx_id(ln_counter)
                        , P_CUSTOMER_ID          => l_customer_id(ln_counter)
                        , P_PAYMENT_SCHEDULE_ID  => l_payment_schedule_id(ln_counter)
                        , P_AMOUNT_DUE_ORIGINAL  => l_amount_due_original(ln_counter)
                        , P_DUE_DATE             => l_due_date(ln_counter)
                        , P_GL_DATE              => l_gl_date(ln_counter)
                        , P_CUSTOMER_SITE_USE_ID => l_customer_site_use_id(ln_counter)
                        , P_TRX_DATE             => l_trx_date(ln_counter)
                        , P_DESCRICAO            => lv_debug ||' '||lv_msg_data
                       )
                   ;
                 END IF;
               END LOOP;
             ELSE
               lv_msg_data := fnd_msg_pub.GET;
               IF lv_msg_data IS NOT NULL THEN
                   LOG_II_P
                       (
                          P_CUSTOMER_TRX_ID      => l_customer_trx_id(ln_counter)
                        , P_CUSTOMER_ID          => l_customer_id(ln_counter)
                        , P_PAYMENT_SCHEDULE_ID  => l_payment_schedule_id(ln_counter)
                        , P_AMOUNT_DUE_ORIGINAL  => l_amount_due_original(ln_counter)
                        , P_DUE_DATE             => l_due_date(ln_counter)
                        , P_GL_DATE              => l_gl_date(ln_counter)
                        , P_CUSTOMER_SITE_USE_ID => l_customer_site_use_id(ln_counter)
                        , P_TRX_DATE             => l_trx_date(ln_counter)
                        , P_DESCRICAO            => lv_debug ||' '||lv_msg_data
                       )
                   ;
               ELSE
                   LOG_II_P
                       (
                          P_CUSTOMER_TRX_ID      => l_customer_trx_id(ln_counter)
                        , P_CUSTOMER_ID          => l_customer_id(ln_counter)
                        , P_PAYMENT_SCHEDULE_ID  => l_payment_schedule_id(ln_counter)
                        , P_AMOUNT_DUE_ORIGINAL  => l_amount_due_original(ln_counter)
                        , P_DUE_DATE             => l_due_date(ln_counter)
                        , P_GL_DATE              => l_gl_date(ln_counter)
                        , P_CUSTOMER_SITE_USE_ID => l_customer_site_use_id(ln_counter)
                        , P_TRX_DATE             => l_trx_date(ln_counter)
                        , P_DESCRICAO            => lv_debug ||' Erro não retornado para a API AR_ADJUST_PUB.CREATE_ADJUSTMENT'
                       )
                   ;
               END IF;
             END IF;
           ELSE
             COMMIT;
             lv_sucs_msg := 'Customer_trx_id:'     || l_customer_trx_id(ln_counter)     ||
                            'Payment_Schedule_id:' || l_payment_schedule_id(ln_counter) ||
                            'Adjustment_id:'       || ln_new_adjustment_id              ||
                            'Adjustment_Number:'   || lv_new_adjustment_number||' AJUSTE CRIADO COM SUCESSO. '
             ;
             fnd_file.put_line (fnd_file.log, lv_sucs_msg);
             dbms_output.put_line(lv_error_msg||' '||lv_msg_data);
             --
           END IF;
         END;
         <<PROXIMO>>
         ln_counter := l_customer_trx_id.NEXT(ln_counter);
         NULL;
       END LOOP;
       EXIT WHEN l_customer_trx_id.COUNT < ln_limit;
     END LOOP;
    CLOSE c_rcta;
    COMMIT;

    fnd_file.put_line (fnd_file.log, 'Total Selecionado no Cursor: '||ln_cnt);

  dbms_output.put_lINe( 'Finalizado em: '||((dbms_utility.get_time - ln_time)/100) || ' seconds....' );
  fnd_file.put_lINe (fnd_file.log, lv_routINe||' - Finalizado em: '||((dbms_utility.get_time - ln_time)/100) || ' seconds....' );

  EXCEPTION
    WHEN OTHERS THEN
      lv_error_msg := lv_debug ||CHR(13)||
                      '  ERRO SÚBITO - '||SQLERRM
      ;
      fnd_file.put_lINe (fnd_file.log, lv_error_msg);
      retcode := 2;
  END CREATE_INV_ADJ_P;

END XXVEN_AR_RCPTS_CREDITCARD_PKG;