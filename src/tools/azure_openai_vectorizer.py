"""Custom Azure OpenAI Text Vectorizer with Azure AD authentication support.

This module provides a custom vectorizer that bypasses the API key requirement
in RedisVL's built-in vectorizers and supports Azure AD token providers.
"""

import logging
import os
from typing import Dict, Any, Optional, List

from redisvl.utils.vectorize.base import BaseVectorizer

# Logger
_logger = logging.getLogger(__name__)


class AzureADOpenAITextVectorizer(BaseVectorizer):
    """Custom Azure OpenAI Text Vectorizer that supports Azure AD authentication.
    
    This follows the same patterns as AzureOpenAITextVectorizer but supports
    Azure AD token providers instead of requiring API keys.
    """
    
    def __init__(
        self,
        model: str = "text-embedding-ada-002",
        api_config: Optional[Dict] = None,
        dtype: str = "float32",
        **kwargs
    ):
        """Initialize the Azure AD OpenAI vectorizer.
        
        Args:
            model: The embedding model deployment name
            api_config: Dictionary containing Azure configuration and credential
            dtype: Default datatype for embeddings
            **kwargs: Additional arguments
        """
        super().__init__(model=model, dtype=dtype, **kwargs)
        # Initialize clients and set up the model (following AzureOpenAITextVectorizer pattern)
        self._setup(api_config, **kwargs)
    
    def _setup(self, api_config: Optional[Dict], **kwargs):
        """Set up the Azure OpenAI clients and determine the embedding dimensions."""
        # Initialize clients
        self._initialize_clients(api_config, **kwargs)
        # Set model dimensions after client initialization
        self.dims = self._set_model_dims()
    
    def _initialize_clients(self, api_config: Optional[Dict], **kwargs):
        """Setup Azure OpenAI clients using Azure AD authentication.
        
        Args:
            api_config: Dictionary with Azure configuration and credential
            **kwargs: Additional arguments to pass to Azure OpenAI clients
            
        Raises:
            ImportError: If the openai library is not installed
            ValueError: If required parameters are not provided
        """
        if api_config is None:
            api_config = {}
        
        # Dynamic import of the openai module (following AzureOpenAITextVectorizer pattern)
        try:
            from openai import AsyncAzureOpenAI, AzureOpenAI
        except ImportError:
            raise ImportError(
                "AzureOpenAI vectorizer requires the openai library. "
                "Please install with `pip install openai>=1.3.0`"
            )
        
        # Get Azure endpoint from api_config or environment variable
        azure_endpoint = (
            api_config.pop("azure_endpoint", None)
            if api_config
            else os.getenv("AZURE_OPENAI_ENDPOINT")
        )
        
        if not azure_endpoint:
            raise ValueError(
                "Azure OpenAI API endpoint is required. "
                "Provide it in api_config['azure_endpoint'] or set the AZURE_OPENAI_ENDPOINT environment variable."
            )
        
        # Get API version from api_config or environment variable
        api_version = (
            api_config.pop("api_version", None)
            if api_config
            else os.getenv("OPENAI_API_VERSION", "2024-10-21")
        )
        
        if not api_version:
            raise ValueError(
                "Azure OpenAI API version is required. "
                "Provide it in api_config['api_version'] or set the OPENAI_API_VERSION environment variable."
            )
        
        # Get Azure credential from api_config
        credential = api_config.pop("credential", None) if api_config else None
        
        if not credential:
            raise ValueError(
                "Azure credential is required. "
                "Provide it in api_config['credential']."
            )
        
        # Create token provider function that includes the required scope for Azure OpenAI
        def azure_ad_token_provider():
            """Token provider function for Azure OpenAI that includes the proper scope."""
            try:
                access_token = credential.get_token("https://cognitiveservices.azure.com/.default")
                _logger.debug(f"Successfully obtained Azure AD token, expires at: {access_token.expires_on}")
                return access_token.token  # Return just the token string, not the AccessToken object
            except Exception as e:
                _logger.error(f"Failed to get Azure AD token: {e}")
                raise
        
        # Create Azure OpenAI clients with Azure AD token provider
        self._client = AzureOpenAI(
            azure_endpoint=azure_endpoint,
            api_version=api_version,
            azure_ad_token_provider=azure_ad_token_provider,
            **api_config,
            **kwargs,
        )
        self._aclient = AsyncAzureOpenAI(
            azure_endpoint=azure_endpoint,
            api_version=api_version,
            azure_ad_token_provider=azure_ad_token_provider,
            **api_config,
            **kwargs,
        )
    
    def _set_model_dims(self) -> int:
        """Determine the dimensionality of the embedding model by making a test call.
        
        Returns:
            int: Dimensionality of the embedding model
            
        Raises:
            ValueError: If embedding dimensions cannot be determined
        """
        try:
            # Call the protected _embed method to avoid caching this test embedding
            embedding = self._embed("dimension check")
            return len(embedding)
        except (KeyError, IndexError) as ke:
            raise ValueError(f"Unexpected response from the Azure OpenAI API: {str(ke)}")
        except Exception as e:
            # Fall back to default for text-embedding-ada-002
            _logger.warning(f"Could not determine embedding dimensions, defaulting to 1536: {e}")
            return 1536
    
    def _embed(self, text: str, **kwargs) -> List[float]:
        """Generate a vector embedding for a single text using Azure OpenAI API.
        
        Args:
            text: Text to embed
            **kwargs: Additional parameters to pass to the Azure OpenAI API
            
        Returns:
            List[float]: Vector embedding as a list of floats
            
        Raises:
            TypeError: If text is not a string
            ValueError: If embedding fails
        """
        if not isinstance(text, str):
            raise TypeError("Must pass in a str value to embed.")
        
        try:
            _logger.debug(f"Making embedding request with model: {self.model}, text length: {len(text)}")
            result = self._client.embeddings.create(
                input=[text], model=self.model, **kwargs
            )
            _logger.debug(f"Embedding request successful, got {len(result.data[0].embedding)} dimensions")
            return result.data[0].embedding
        except Exception as e:
            _logger.error(f"Embedding request failed for model '{self.model}': {e}")
            raise ValueError(f"Embedding text failed: {e}")
    
    def _embed_many(
        self, texts: List[str], batch_size: int = 10, **kwargs
    ) -> List[List[float]]:
        """Generate vector embeddings for a batch of texts using Azure OpenAI API.
        
        Args:
            texts: List of texts to embed
            batch_size: Number of texts to process in each API call
            **kwargs: Additional parameters to pass to the Azure OpenAI API
            
        Returns:
            List[List[float]]: List of vector embeddings as lists of floats
            
        Raises:
            TypeError: If texts is not a list of strings
            ValueError: If embedding fails
        """
        if not isinstance(texts, list):
            raise TypeError("Must pass in a list of str values to embed.")
        if texts and not isinstance(texts[0], str):
            raise TypeError("Must pass in a list of str values to embed.")
        
        try:
            embeddings: List = []
            for batch in self.batchify(texts, batch_size):
                response = self._client.embeddings.create(
                    input=batch, model=self.model, **kwargs
                )
                embeddings.extend([r.embedding for r in response.data])
            return embeddings
        except Exception as e:
            raise ValueError(f"Embedding texts failed: {e}")
    
    async def _aembed(self, text: str, **kwargs) -> List[float]:
        """Asynchronously generate a vector embedding for a single text.
        
        Args:
            text: Text to embed
            **kwargs: Additional parameters to pass to the Azure OpenAI API
            
        Returns:
            List[float]: Vector embedding as a list of floats
            
        Raises:
            TypeError: If text is not a string
            ValueError: If embedding fails
        """
        if not isinstance(text, str):
            raise TypeError("Must pass in a str value to embed.")
        
        try:
            result = await self._aclient.embeddings.create(
                input=[text], model=self.model, **kwargs
            )
            return result.data[0].embedding
        except Exception as e:
            raise ValueError(f"Embedding text failed: {e}")
    
    async def _aembed_many(
        self, texts: List[str], batch_size: int = 10, **kwargs
    ) -> List[List[float]]:
        """Asynchronously generate vector embeddings for a batch of texts.
        
        Args:
            texts: List of texts to embed
            batch_size: Number of texts to process in each API call
            **kwargs: Additional parameters to pass to the Azure OpenAI API
            
        Returns:
            List[List[float]]: List of vector embeddings as lists of floats
            
        Raises:
            TypeError: If texts is not a list of strings
            ValueError: If embedding fails
        """
        if not isinstance(texts, list):
            raise TypeError("Must pass in a list of str values to embed.")
        if texts and not isinstance(texts[0], str):
            raise TypeError("Must pass in a list of str values to embed.")
        
        try:
            embeddings: List = []
            for batch in self.batchify(texts, batch_size):
                response = await self._aclient.embeddings.create(
                    input=batch, model=self.model, **kwargs
                )
                embeddings.extend([r.embedding for r in response.data])
            return embeddings
        except Exception as e:
            raise ValueError(f"Embedding texts failed: {e}")
    
    @property
    def type(self) -> str:
        return "azure_openai_ad"